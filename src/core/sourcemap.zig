const std = @import("std");

/// Represents a single mapping in the source map
pub const Mapping = struct {
    generated_line: i32,
    generated_column: i32,
    source_line: i32,
    source_column: i32,
};

/// Source map structure containing mappings in VLQ format
pub const SourceMap = struct {
    mappings: []const u8,

    pub fn deinit(self: *SourceMap, allocator: std.mem.Allocator) void {
        allocator.free(self.mappings);
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
