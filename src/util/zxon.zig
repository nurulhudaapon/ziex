//! ZXON - ZX Object Notation (Ziex Exchange Object Notation)
//!
//! A compact positional serialization format for Zig types. Structs are encoded
//! as ordered value arrays `[field1, field2, ...]` - field names are known at
//! comptime on both ends, so only values are transmitted.
//!
//! Compared to `std.json`, this pulls in ~78 KB less code in WASM builds.

const std = @import("std");

/// Options for serialize/parse - reserved for future use.
pub const Options = struct {};

// ──────────────────────────────────────────────────────────────
//  Serialize
// ──────────────────────────────────────────────────────────────

/// Serialize `value` into ZXON positional format.
pub fn serialize(value: anytype, writer: *std.Io.Writer, options: Options) anyerror!void {
    _ = options;
    return writeValue(@TypeOf(value), value, writer);
}

fn writeValue(comptime T: type, value: T, w: *std.Io.Writer) anyerror!void {
    switch (@typeInfo(T)) {
        .@"struct" => |s| {
            try w.writeByte('[');
            inline for (s.fields, 0..) |field, i| {
                if (i > 0) try w.writeByte(',');
                try writeValue(field.type, @field(value, field.name), w);
            }
            try w.writeByte(']');
        },
        .optional => |opt| {
            if (value) |v| try writeValue(opt.child, v, w) else try w.writeAll("null");
        },
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8) {
                try writeStr(w, value);
            } else if (ptr.size == .slice) {
                try w.writeByte('[');
                for (value, 0..) |item, i| {
                    if (i > 0) try w.writeByte(',');
                    try writeValue(ptr.child, item, w);
                }
                try w.writeByte(']');
            } else if (ptr.size == .one and @typeInfo(ptr.child) == .array and @typeInfo(ptr.child).array.child == u8) {
                try writeStrLiteral(w, value);
            } else {
                try w.writeAll("null");
            }
        },
        .array => |arr| {
            try w.writeByte('[');
            for (value, 0..) |item, i| {
                if (i > 0) try w.writeByte(',');
                try writeValue(arr.child, item, w);
            }
            try w.writeByte(']');
        },
        .int, .comptime_int => try w.print("{d}", .{value}),
        .float, .comptime_float => try w.print("{d}", .{value}),
        .bool => try w.writeAll(if (value) "true" else "false"),
        .@"enum" => try w.print("{d}", .{@intFromEnum(value)}),
        else => try w.writeAll("null"),
    }
}

fn writeStr(w: *std.Io.Writer, bytes: []const u8) !void {
    try w.writeByte('"');
    for (bytes) |c| try escapeByte(w, c);
    try w.writeByte('"');
}

fn writeStrLiteral(w: *std.Io.Writer, value: anytype) !void {
    try w.writeByte('"');
    for (value) |c| {
        if (c == 0) break;
        try escapeByte(w, c);
    }
    try w.writeByte('"');
}

inline fn escapeByte(w: *std.Io.Writer, c: u8) !void {
    switch (c) {
        '"' => try w.writeAll("\\\""),
        '\\' => try w.writeAll("\\\\"),
        '\n' => try w.writeAll("\\n"),
        '\r' => try w.writeAll("\\r"),
        '\t' => try w.writeAll("\\t"),
        else => try w.writeByte(c),
    }
}

// ──────────────────────────────────────────────────────────────
//  Parse
// ──────────────────────────────────────────────────────────────

/// Parse a ZXON-encoded `string` into a value of type `T`.
pub fn parse(comptime T: type, allocator: std.mem.Allocator, data: []const u8, options: Options) !T {
    _ = options;
    var pos: usize = 0;
    skip(data, &pos);
    return readValue(T, allocator, data, &pos);
}

fn readValue(comptime T: type, allocator: std.mem.Allocator, d: []const u8, p: *usize) anyerror!T {
    switch (@typeInfo(T)) {
        .@"struct" => |s| {
            if (peek(d, p) != '[') return error.ExpectedArrayStart;
            p.* += 1;
            skip(d, p);

            var result: T = undefined;
            inline for (s.fields, 0..) |field, i| {
                if (i > 0) comma(d, p);
                @field(result, field.name) = try readValue(field.type, allocator, d, p);
            }

            skip(d, p);
            if (peek(d, p) != ']') return error.ExpectedArrayEnd;
            p.* += 1;
            return result;
        },
        .optional => |opt| {
            if (literal(d, p, "null")) return null;
            return try readValue(opt.child, allocator, d, p);
        },
        .pointer => |ptr| {
            if (ptr.size != .slice) return error.UnsupportedType;
            if (ptr.child == u8) return readStr(allocator, d, p);
            return readSlice(ptr.child, allocator, d, p);
        },
        .array => |arr| {
            if (peek(d, p) != '[') return error.ExpectedArrayStart;
            p.* += 1;
            skip(d, p);

            var result: T = undefined;
            for (&result, 0..) |*item, i| {
                if (i > 0) comma(d, p);
                item.* = try readValue(arr.child, allocator, d, p);
            }

            skip(d, p);
            if (peek(d, p) != ']') return error.ExpectedArrayEnd;
            p.* += 1;
            return result;
        },
        .int => return readInt(T, d, p),
        .float => return readFloat(T, d, p),
        .bool => {
            if (literal(d, p, "true")) return true;
            if (literal(d, p, "false")) return false;
            return false;
        },
        .@"enum" => |e| return @enumFromInt(readInt(e.tag_type, d, p) catch 0),
        else => return error.UnsupportedType,
    }
}

fn readSlice(comptime Child: type, allocator: std.mem.Allocator, d: []const u8, p: *usize) anyerror![]Child {
    if (peek(d, p) != '[') return error.ExpectedArrayStart;
    p.* += 1;
    skip(d, p);

    if (peek(d, p) == ']') {
        p.* += 1;
        return try allocator.alloc(Child, 0);
    }

    var list = std.array_list.Managed(Child).init(allocator);
    errdefer list.deinit();

    while (p.* < d.len) {
        try list.append(try readValue(Child, allocator, d, p));
        skip(d, p);

        if (peek(d, p) == ',') {
            p.* += 1;
            skip(d, p);
        } else if (peek(d, p) == ']') {
            p.* += 1;
            return list.toOwnedSlice();
        } else {
            return error.ExpectedArrayEnd;
        }
    }
    return error.UnexpectedEnd;
}

fn readStr(allocator: std.mem.Allocator, d: []const u8, p: *usize) ![]const u8 {
    if (peek(d, p) != '"') return error.ExpectedString;
    p.* += 1;

    const start = p.*;
    var has_escapes = false;

    while (p.* < d.len and d[p.*] != '"') {
        if (d[p.*] == '\\') {
            has_escapes = true;
            p.* += 2;
        } else {
            p.* += 1;
        }
    }

    const end = p.*;
    if (p.* < d.len) p.* += 1; // closing quote

    if (!has_escapes) return allocator.dupe(u8, d[start..end]) catch "";

    var buf: [4096]u8 = undefined;
    var len: usize = 0;
    var i = start;
    while (i < end and len < buf.len) {
        if (d[i] == '\\' and i + 1 < end) {
            buf[len] = switch (d[i + 1]) {
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                '"' => '"',
                '\\' => '\\',
                else => d[i + 1],
            };
            len += 1;
            i += 2;
        } else {
            buf[len] = d[i];
            len += 1;
            i += 1;
        }
    }
    return allocator.dupe(u8, buf[0..len]) catch "";
}

fn readInt(comptime T: type, d: []const u8, p: *usize) !T {
    skip(d, p);
    const start = p.*;

    if (peek(d, p) == '-') p.* += 1;
    while (p.* < d.len and d[p.*] >= '0' and d[p.*] <= '9') p.* += 1;

    if (p.* == start or (d[start] == '-' and p.* == start + 1)) return 0;
    return std.fmt.parseInt(T, d[start..p.*], 10) catch 0;
}

fn readFloat(comptime T: type, d: []const u8, p: *usize) !T {
    skip(d, p);
    const start = p.*;

    if (peek(d, p) == '-') p.* += 1;
    while (p.* < d.len) {
        switch (d[p.*]) {
            '0'...'9', '.', 'e', 'E', '+', '-' => p.* += 1,
            else => break,
        }
    }

    if (p.* == start) return 0;
    return std.fmt.parseFloat(T, d[start..p.*]) catch 0;
}

// ── Helpers ──────────────────────────────────────────────────

fn peek(d: []const u8, p: *const usize) u8 {
    return if (p.* < d.len) d[p.*] else 0;
}

fn skip(d: []const u8, p: *usize) void {
    while (p.* < d.len) {
        switch (d[p.*]) {
            ' ', '\t', '\n', '\r' => p.* += 1,
            else => break,
        }
    }
}

fn comma(d: []const u8, p: *usize) void {
    skip(d, p);
    if (peek(d, p) == ',') p.* += 1;
    skip(d, p);
}

fn literal(d: []const u8, p: *usize, lit: []const u8) bool {
    if (p.* + lit.len <= d.len and std.mem.eql(u8, d[p.*..][0..lit.len], lit)) {
        p.* += lit.len;
        return true;
    }
    return false;
}

// ──────────────────────────────────────────────────────────────
//  Schema
// ──────────────────────────────────────────────────────────────

/// Returns a comptime structural schema descriptor for `T`.
/// The hash uniquely identifies the field-name / type structure so that
/// mismatched serializer–parser pairs can be detected.
pub fn schema(comptime T: type) struct { hash: u64 } {
    return comptime .{ .hash = computeHash(T) };
}

fn computeHash(comptime T: type) u64 {
    comptime {
        const s = typeSignature(T);
        var hash: u64 = 14695981039346656037; // FNV-1a offset basis
        for (s) |b| {
            hash ^= b;
            hash *%= 1099511628211;
        }
        return hash;
    }
}

fn typeSignature(comptime T: type) []const u8 {
    comptime {
        return switch (@typeInfo(T)) {
            .@"struct" => |s| blk: {
                var r: []const u8 = "struct{";
                for (s.fields) |f| r = r ++ f.name ++ ":" ++ typeSignature(f.type) ++ ";";
                break :blk r ++ "}";
            },
            .optional => |opt| "?" ++ typeSignature(opt.child),
            .pointer => |ptr| if (ptr.size == .slice) "[]" ++ typeSignature(ptr.child) else "*" ++ typeSignature(ptr.child),
            .array => |arr| "[N]" ++ typeSignature(arr.child),
            else => @typeName(T),
        };
    }
}
