const std = @import("std");

/// Represents a single mapping in the source map
pub const Mapping = struct {
    generated_line: i32,
    generated_column: i32,
    source_line: i32,
    source_column: i32,
};

/// Decoded sourcemap with lookup capabilities for position remapping.
pub const DecodedMap = struct {
    entries: []const Mapping,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *DecodedMap) void {
        self.allocator.free(self.entries);
    }

    /// Map a source (original .zx) position to the generated (.zig) position.
    /// Returns the closest mapping at or before the given source position.
    pub fn sourceToGenerated(self: DecodedMap, line: i32, column: i32) ?Mapping {
        var best: ?Mapping = null;
        var is_exact = false;

        for (self.entries) |m| {
            if (m.source_line == line and m.source_column == column) {
                if (!is_exact or m.generated_line < best.?.generated_line or
                    (m.generated_line == best.?.generated_line and m.generated_column < best.?.generated_column))
                {
                    best = m;
                    is_exact = true;
                }
                continue;
            }

            if (is_exact) continue; // Exact matches are always better than "at or before"

            if (m.source_line > line) continue;
            if (m.source_line == line and m.source_column > column) continue;

            if (best) |b| {
                if (m.source_line > b.source_line or
                    (m.source_line == b.source_line and m.source_column > b.source_column))
                {
                    best = m;
                }
            } else {
                best = m;
            }
        }

        if (best) |b| {
            // Adjust the generated column by the offset from the exact mapping point
            const col_offset = if (b.source_line == line) column - b.source_column else 0;
            return .{
                .generated_line = b.generated_line,
                .generated_column = b.generated_column + col_offset,
                .source_line = line,
                .source_column = column,
            };
        }
        return null;
    }

    /// Map a generated (.zig) position back to the source (original .zx) position.
    /// Returns the closest mapping at or before the given generated position.
    pub fn generatedToSource(self: DecodedMap, line: i32, column: i32) ?Mapping {
        var low: usize = 0;
        var high: usize = self.entries.len;
        var best: ?Mapping = null;

        while (low < high) {
            const mid = low + (high - low) / 2;
            const m = self.entries[mid];

            if (m.generated_line < line or (m.generated_line == line and m.generated_column <= column)) {
                best = m;
                low = mid + 1;
            } else {
                high = mid;
            }
        }

        if (best) |b| {
            const col_offset = if (b.generated_line == line) column - b.generated_column else 0;
            return .{
                .generated_line = line,
                .generated_column = column,
                .source_line = b.source_line,
                .source_column = b.source_column + col_offset,
            };
        }
        return null;
    }
};

/// Source map structure containing mappings in VLQ format
pub const SourceMap = struct {
    mappings: []const u8,

    pub fn deinit(self: *SourceMap, allocator: std.mem.Allocator) void {
        allocator.free(self.mappings);
    }

    /// Decode VLQ-encoded mappings into a DecodedMap with lookup capabilities.
    pub fn decode(self: SourceMap, allocator: std.mem.Allocator) !DecodedMap {
        var result = std.array_list.Managed(Mapping).init(allocator);
        errdefer result.deinit();

        var gen_line: i32 = 0;
        var gen_col: i32 = 0;
        var src_line: i32 = 0;
        var src_col: i32 = 0;

        var i: usize = 0;
        while (i < self.mappings.len) {
            const ch = self.mappings[i];
            if (ch == ';') {
                gen_line += 1;
                gen_col = 0;
                i += 1;
                continue;
            }
            if (ch == ',') {
                i += 1;
                continue;
            }

            // Decode segment: generated_column, source_index, source_line, source_column
            const gen_col_delta = decodeVLQ(self.mappings, &i) orelse break;
            gen_col += gen_col_delta;

            // Must have at least source_index, source_line, source_column
            if (i >= self.mappings.len or self.mappings[i] == ';' or self.mappings[i] == ',') {
                // No source mapping for this segment, skip
                continue;
            }

            _ = decodeVLQ(self.mappings, &i) orelse break; // source_index (always 0)
            const src_line_delta = decodeVLQ(self.mappings, &i) orelse break;
            const src_col_delta = decodeVLQ(self.mappings, &i) orelse break;

            src_line += src_line_delta;
            src_col += src_col_delta;

            try result.append(.{
                .generated_line = gen_line,
                .generated_column = gen_col,
                .source_line = src_line,
                .source_column = src_col,
            });
        }

        return .{
            .entries = try result.toOwnedSlice(),
            .allocator = allocator,
        };
    }

    /// Convert source map to JSON format
    /// generated_file: name of the generated file (e.g., "output.zig")
    /// source_file: name of the source file (e.g., "input.zx")
    /// source_content: original source content
    /// generated_content: optional generated content (for standalone sourcemaps)
    pub fn toJSON(
        self: SourceMap,
        allocator: std.mem.Allocator,
        generated_file: []const u8,
        source_file: []const u8,
        source_content: []const u8,
        generated_content: ?[]const u8,
    ) ![]const u8 {
        var json = std.array_list.Managed(u8).init(allocator);
        errdefer json.deinit();

        const writer = json.writer();
        try writer.writeAll("{\"version\":3,\"file\":\"");
        try escapeJSONString(writer, generated_file);
        try writer.writeAll("\",\"sources\":[\"");
        try escapeJSONString(writer, source_file);
        try writer.writeAll("\"],\"sourcesContent\":[\"");
        try escapeJSONString(writer, source_content);
        try writer.writeAll("\"]");

        // Optionally include generated content (not standard but some tools support it)
        if (generated_content) |gen_content| {
            try writer.writeAll(",\"x_generatedContent\":\"");
            try escapeJSONString(writer, gen_content);
            try writer.writeAll("\"");
        }

        try writer.writeAll(",\"mappings\":\"");
        try escapeJSONString(writer, self.mappings);
        try writer.writeAll("\"}");

        return json.toOwnedSlice();
    }
};

/// Builder for creating source maps from mappings
pub const Builder = struct {
    mappings: std.array_list.Managed(Mapping),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Builder {
        return .{
            .mappings = std.array_list.Managed(Mapping).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Builder) void {
        self.mappings.deinit();
    }

    /// Add a mapping to the source map
    pub fn addMapping(self: *Builder, mapping: Mapping) !void {
        try self.mappings.append(mapping);
    }

    /// Finalize and build the source map with VLQ-encoded mappings
    pub fn build(self: *Builder) !SourceMap {
        var mappings_str = std.array_list.Managed(u8).init(self.allocator);
        errdefer mappings_str.deinit();

        var prev_gen_line: i32 = 0;
        var prev_gen_col: i32 = 0;
        var prev_src_line: i32 = 0;
        var prev_src_col: i32 = 0;

        for (self.mappings.items, 0..) |mapping, idx| {
            // Add semicolons for line breaks
            while (prev_gen_line < mapping.generated_line) {
                try mappings_str.append(';');
                prev_gen_line += 1;
                prev_gen_col = 0;
            }

            // Add comma between mappings on same line
            if (idx > 0 and mapping.generated_line == prev_gen_line) {
                try mappings_str.append(',');
            }

            // Encode VLQ values
            try encodeVLQ(&mappings_str, mapping.generated_column - prev_gen_col);
            try encodeVLQ(&mappings_str, 0); // source index (always 0)
            try encodeVLQ(&mappings_str, mapping.source_line - prev_src_line);
            try encodeVLQ(&mappings_str, mapping.source_column - prev_src_col);

            prev_gen_col = mapping.generated_column;
            prev_src_line = mapping.source_line;
            prev_src_col = mapping.source_column;
        }

        return SourceMap{
            .mappings = try mappings_str.toOwnedSlice(),
        };
    }
};

/// Escape a string for JSON output
fn escapeJSONString(writer: anytype, s: []const u8) !void {
    for (s) |byte| {
        switch (byte) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            '\x08' => try writer.writeAll("\\b"),
            '\x0c' => try writer.writeAll("\\f"),
            else => {
                // Control characters (0x00-0x1f) that aren't already handled
                if (byte < 0x20) {
                    const hex_digits = "0123456789abcdef";
                    try writer.writeAll("\\u00");
                    try writer.writeByte(hex_digits[(byte >> 4) & 0xf]);
                    try writer.writeByte(hex_digits[byte & 0xf]);
                } else {
                    try writer.writeByte(byte);
                }
            },
        }
    }
}

/// Decode a single VLQ value from a base64-encoded mappings string.
/// Advances `pos` past the consumed characters. Returns null if no valid VLQ found.
fn decodeVLQ(data: []const u8, pos: *usize) ?i32 {
    var result: u32 = 0;
    var shift: u5 = 0;

    while (pos.* < data.len) {
        const ch = data[pos.*];
        const digit = base64Decode(ch) orelse return null;
        pos.* += 1;

        result |= @as(u32, digit & 31) << shift;
        if (digit & 32 == 0) {
            // Sign bit is the LSB of the result
            const is_negative = (result & 1) != 0;
            const magnitude = result >> 1;
            return if (is_negative) -@as(i32, @intCast(magnitude)) else @as(i32, @intCast(magnitude));
        }
        shift +|= 5;
    }
    return null;
}

fn base64Decode(ch: u8) ?u6 {
    return switch (ch) {
        'A'...'Z' => @intCast(ch - 'A'),
        'a'...'z' => @intCast(ch - 'a' + 26),
        '0'...'9' => @intCast(ch - '0' + 52),
        '+' => 62,
        '/' => 63,
        else => null,
    };
}

/// Encode an integer value as VLQ (Variable-Length Quantity) base64
fn encodeVLQ(list: *std.array_list.Managed(u8), value: i32) !void {
    const base64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    var vlq: u32 = if (value < 0)
        @as(u32, @intCast((-value) << 1)) | 1
    else
        @as(u32, @intCast(value << 1));

    while (true) {
        var digit: u32 = vlq & 31;
        vlq >>= 5;

        if (vlq > 0) {
            digit |= 32; // continuation bit
        }

        try list.append(base64_chars[@intCast(digit)]);

        if (vlq == 0) break;
    }
}
