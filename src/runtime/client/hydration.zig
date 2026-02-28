const std = @import("std");

/// MinimalArrayParser - Parses positional array format for component props
/// Format: [val1, val2, ...] where values are in struct field order
/// ~78KB smaller than std.json for WASM builds
pub const PropsParser = struct {
    data: []const u8,
    pos: usize = 0,

    pub fn init(data: []const u8) PropsParser {
        return .{ .data = data };
    }

    pub fn parse(self: *PropsParser, comptime T: type, allocator: std.mem.Allocator) !T {
        self.skipWhitespace();
        return self.parseValue(T, allocator);
    }

    fn parseValue(self: *PropsParser, comptime T: type, allocator: std.mem.Allocator) anyerror!T {
        const type_info = @typeInfo(T);

        switch (type_info) {
            .@"struct" => |s| {
                // Structs are serialized as arrays
                if (self.current() != '[') return error.ExpectedArrayStart;
                self.pos += 1;
                self.skipWhitespace();

                var result: T = undefined;
                inline for (s.fields, 0..) |field, i| {
                    if (i > 0) {
                        self.skipWhitespace();
                        if (self.current() == ',') self.pos += 1;
                        self.skipWhitespace();
                    }
                    @field(result, field.name) = try self.parseValue(field.type, allocator);
                }

                self.skipWhitespace();
                if (self.current() != ']') return error.ExpectedArrayEnd;
                self.pos += 1;
                return result;
            },
            .optional => |opt| {
                if (self.matchLiteral("null")) return null;
                return try self.parseValue(opt.child, allocator);
            },
            .pointer => |ptr| {
                if (ptr.size == .slice) {
                    if (ptr.child == u8) {
                        return self.parseString(allocator);
                    }

                    if (self.current() != '[') return error.ExpectedArrayStart;
                    self.pos += 1;
                    self.skipWhitespace();

                    if (self.current() == ']') {
                        self.pos += 1;
                        return &.{};
                    }

                    var list = std.array_list.Managed(ptr.child).init(allocator);
                    errdefer list.deinit();

                    while (self.pos < self.data.len) {
                        const val = try self.parseValue(ptr.child, allocator);
                        try list.append(val);

                        self.skipWhitespace();
                        if (self.current() == ',') {
                            self.pos += 1;
                            self.skipWhitespace();
                        } else if (self.current() == ']') {
                            self.pos += 1;
                            return list.toOwnedSlice();
                        } else {
                            return error.ExpectedArrayEnd;
                        }
                    }
                    return error.UnexpectedEnd;
                }
                return error.UnsupportedType;
            },
            .array => |arr| {
                if (self.current() != '[') return error.ExpectedArrayStart;
                self.pos += 1;
                self.skipWhitespace();

                var result: T = undefined;
                for (&result, 0..) |*item, i| {
                    if (i > 0) {
                        self.skipWhitespace();
                        if (self.current() == ',') self.pos += 1;
                        self.skipWhitespace();
                    }
                    item.* = try self.parseValue(arr.child, allocator);
                }

                self.skipWhitespace();
                if (self.current() != ']') return error.ExpectedArrayEnd;
                self.pos += 1;
                return result;
            },
            .int => return self.parseInt(T),
            .float => return self.parseFloat(T),
            .bool => {
                if (self.matchLiteral("true")) return true;
                if (self.matchLiteral("false")) return false;
                return false;
            },
            .@"enum" => |e| {
                const int_val = self.parseInt(e.tag_type) catch 0;
                return @enumFromInt(int_val);
            },
            else => return error.UnsupportedType,
        }
    }

    fn parseString(self: *PropsParser, allocator: std.mem.Allocator) ![]const u8 {
        if (self.current() != '"') return error.ExpectedString;
        self.pos += 1;

        const start = self.pos;
        var has_escapes = false;

        while (self.pos < self.data.len and self.data[self.pos] != '"') {
            if (self.data[self.pos] == '\\') {
                has_escapes = true;
                self.pos += 2; // Skip escape sequence
            } else {
                self.pos += 1;
            }
        }

        const end = self.pos;
        if (self.pos < self.data.len) self.pos += 1; // Skip closing quote

        if (!has_escapes) {
            return allocator.dupe(u8, self.data[start..end]) catch "";
        }

        // Handle escapes - build result manually
        var result_buf: [4096]u8 = undefined;
        var result_len: usize = 0;
        var i = start;
        while (i < end and result_len < result_buf.len) {
            if (self.data[i] == '\\' and i + 1 < end) {
                result_buf[result_len] = switch (self.data[i + 1]) {
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    '"' => '"',
                    '\\' => '\\',
                    else => self.data[i + 1],
                };
                result_len += 1;
                i += 2;
            } else {
                result_buf[result_len] = self.data[i];
                result_len += 1;
                i += 1;
            }
        }

        return allocator.dupe(u8, result_buf[0..result_len]) catch "";
    }

    fn parseInt(self: *PropsParser, comptime T: type) !T {
        self.skipWhitespace();
        const start = self.pos;
        var is_negative = false;

        if (self.current() == '-') {
            is_negative = true;
            self.pos += 1;
        }

        while (self.pos < self.data.len) {
            const c = self.data[self.pos];
            if (c >= '0' and c <= '9') {
                self.pos += 1;
            } else {
                break;
            }
        }

        if (self.pos == start or (is_negative and self.pos == start + 1)) {
            return 0;
        }

        return std.fmt.parseInt(T, self.data[start..self.pos], 10) catch 0;
    }

    fn parseFloat(self: *PropsParser, comptime T: type) !T {
        self.skipWhitespace();
        const start = self.pos;

        if (self.current() == '-') self.pos += 1;

        while (self.pos < self.data.len) {
            const c = self.data[self.pos];
            if ((c >= '0' and c <= '9') or c == '.' or c == 'e' or c == 'E' or c == '+' or c == '-') {
                self.pos += 1;
            } else {
                break;
            }
        }

        if (self.pos == start) return 0;
        return std.fmt.parseFloat(T, self.data[start..self.pos]) catch 0;
    }

    fn matchLiteral(self: *PropsParser, literal: []const u8) bool {
        if (self.pos + literal.len <= self.data.len) {
            if (std.mem.eql(u8, self.data[self.pos..][0..literal.len], literal)) {
                self.pos += literal.len;
                return true;
            }
        }
        return false;
    }

    fn skipWhitespace(self: *PropsParser) void {
        while (self.pos < self.data.len) {
            const c = self.data[self.pos];
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                self.pos += 1;
            } else {
                break;
            }
        }
    }

    fn current(self: *PropsParser) u8 {
        return if (self.pos < self.data.len) self.data[self.pos] else 0;
    }
};

/// Parse props from positional array format: [val1, val2, ...]
/// Field names are known at compile time, so we only need values in order.
/// Returns zeroed props on parse failure.
pub fn parseProps(comptime PropT: type, allocator: std.mem.Allocator, props_json: ?[]const u8) PropT {
    if (props_json) |json_bytes| {
        var parser = PropsParser.init(json_bytes);
        return parser.parse(PropT, allocator) catch std.mem.zeroes(PropT);
    }
    return std.mem.zeroes(PropT);
}
