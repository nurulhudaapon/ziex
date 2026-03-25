const std = @import("std");
const zx = @import("zx");

const Builder = @import("Builder.zig");
const tui = @import("../../tui/main.zig");

const Colors = tui.Colors;
const log = std.log.scoped(.diagnostics);
const sourcemap = zx.sourcemap;
const base64 = std.base64.standard;
const SOURCEMAP_PREFIX = "//# sourceMappingURL=data:application/json;base64,";

/// Remap diagnostics from generated .zig files back to original .zx source files
/// using inlined sourcemaps. Modifies diagnostics in-place (replaces file/line/col).
pub fn remap(allocator: std.mem.Allocator, diagnostics: []Builder.Diagnostic) void {
    for (diagnostics) |*d| {
        remapSingle(allocator, d) catch |err| {
            log.debug("sourcemap remap failed for {s}: {s}", .{ d.file, @errorName(err) });
        };
    }
}

fn remapSingle(allocator: std.mem.Allocator, d: *Builder.Diagnostic) !void {
    // Read the generated file and look for inlined sourcemap
    const file_content = std.fs.cwd().readFileAlloc(allocator, d.file, 10 * 1024 * 1024) catch return;
    defer allocator.free(file_content);

    // Find the sourcemap comment (last occurrence)
    const prefix_pos = std.mem.lastIndexOf(u8, file_content, SOURCEMAP_PREFIX) orelse return;
    const b64_start = prefix_pos + SOURCEMAP_PREFIX.len;
    const b64_end = std.mem.indexOfScalarPos(u8, file_content, b64_start, '\n') orelse file_content.len;
    const b64_data = file_content[b64_start..b64_end];

    // Decode base64
    const decoded_len = base64.Decoder.calcSizeForSlice(b64_data) catch return;
    const decoded = allocator.alloc(u8, decoded_len) catch return;
    defer allocator.free(decoded);
    base64.Decoder.decode(decoded, b64_data) catch return;

    // Parse JSON sourcemap — extract "sources" and "mappings" fields
    const source_file = extractJsonStringField(decoded, "sources") orelse return;
    const mappings_str = extractJsonStringField(decoded, "mappings") orelse return;

    // Decode the VLQ mappings
    const sm = sourcemap.SourceMap{ .mappings = mappings_str };
    var decoded_map = sm.decode(allocator) catch return;
    defer decoded_map.deinit();

    // Remap: zig line/col are 1-based, sourcemap is 0-based
    const gen_line: i32 = @as(i32, @intCast(d.line)) - 1;
    const gen_col: i32 = @as(i32, @intCast(d.col)) - 1;
    const mapping = decoded_map.generatedToSource(gen_line, gen_col) orelse return;

    // Replace file and line/col
    const new_file = allocator.dupe(u8, source_file) catch return;
    allocator.free(d.file);
    d.file = new_file;
    d.line = @intCast(mapping.source_line + 1);
    const col_val: u32 = if (mapping.source_column >= 0) @intCast(mapping.source_column + 1) else 1;
    d.col = col_val;

    // Clear pinpoint info as they refer to the generated file context
    if (d.source_line) |sl| {
        allocator.free(sl);
        d.source_line = null;
    }
    if (d.caret_line) |cl| {
        allocator.free(cl);
        d.caret_line = null;
    }
}

/// Extract a string value from a JSON object for a given key.
/// Handles the first occurrence of "sources":["value"] or "mappings":"value".
fn extractJsonStringField(json: []const u8, key: []const u8) ?[]const u8 {
    // Search for "key":
    var i: usize = 0;
    while (i + key.len + 3 < json.len) : (i += 1) {
        if (json[i] == '"' and i + 1 + key.len < json.len and
            std.mem.eql(u8, json[i + 1 .. i + 1 + key.len], key) and
            json[i + 1 + key.len] == '"')
        {
            var pos = i + 1 + key.len + 1; // past closing quote
            // Skip whitespace and colon
            while (pos < json.len and (json[pos] == ':' or json[pos] == ' ' or json[pos] == '\t')) : (pos += 1) {}
            if (pos >= json.len) return null;

            if (json[pos] == '[') {
                // Array: find first string element ["value"]
                pos += 1;
                while (pos < json.len and json[pos] != '"') : (pos += 1) {}
            }

            if (pos < json.len and json[pos] == '"') {
                pos += 1;
                const start = pos;
                while (pos < json.len and json[pos] != '"') : (pos += 1) {
                    if (json[pos] == '\\') pos += 1; // skip escaped chars
                }
                return json[start..pos];
            }
        }
    }
    return null;
}

/// Read a few lines of source context around a given line number.
pub fn readSourceContext(allocator: std.mem.Allocator, file_path: []const u8, target_line: u32, context_lines: u32) ?[]const u8 {
    const source = std.fs.cwd().readFileAlloc(allocator, file_path, 10 * 1024 * 1024) catch return null;
    defer allocator.free(source);

    const start_line = if (target_line > context_lines) target_line - context_lines else 1;
    const end_line = target_line + context_lines;

    var buf = std.ArrayList(u8).empty;
    var line_num: u32 = 1;
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        if (line_num >= start_line and line_num <= end_line) {
            // Line number prefix
            const prefix = std.fmt.allocPrint(allocator, "{d: >4} | ", .{line_num}) catch return null;
            defer allocator.free(prefix);
            buf.appendSlice(allocator, prefix) catch return null;
            buf.appendSlice(allocator, line) catch return null;
            buf.append(allocator, '\n') catch return null;

            // Add caret line for the error line
            if (line_num == target_line) {
                buf.appendSlice(allocator, "     | ") catch return null;
                // We don't have exact col info here so skip caret
            }
        }
        if (line_num > end_line) break;
        line_num += 1;
    }
    return buf.toOwnedSlice(allocator) catch null;
}

/// Build a structured JSON payload for the error overlay.
pub fn toJson(allocator: std.mem.Allocator, diagnostics: []const Builder.Diagnostic) ![]u8 {
    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(allocator);

    try buf.appendSlice(allocator, "{\"type\":\"error\",\"diagnostics\":[");
    for (diagnostics, 0..) |d, idx| {
        if (idx > 0) try buf.append(allocator, ',');
        try buf.appendSlice(allocator, "{\"file\":\"");
        try jsonEscapeAppend(allocator, &buf, d.file);
        try buf.appendSlice(allocator, "\",\"line\":");
        const line_str = try std.fmt.allocPrint(allocator, "{d}", .{d.line});
        defer allocator.free(line_str);
        try buf.appendSlice(allocator, line_str);
        try buf.appendSlice(allocator, ",\"col\":");
        const col_str = try std.fmt.allocPrint(allocator, "{d}", .{d.col});
        defer allocator.free(col_str);
        try buf.appendSlice(allocator, col_str);
        try buf.appendSlice(allocator, ",\"kind\":\"");
        const kind_str: []const u8 = switch (d.kind) {
            .@"error" => "error",
            .warning => "warning",
            .note => "note",
        };
        try buf.appendSlice(allocator, kind_str);
        try buf.appendSlice(allocator, "\",\"message\":\"");
        try jsonEscapeAppend(allocator, &buf, d.message);
        try buf.appendSlice(allocator, "\"");

        // Add source context for error diagnostics
        if (d.kind == .@"error") {
            if (readSourceContext(allocator, d.file, d.line, 3)) |ctx| {
                defer allocator.free(ctx);
                try buf.appendSlice(allocator, ",\"source\":\"");
                try jsonEscapeAppend(allocator, &buf, ctx);
                try buf.appendSlice(allocator, "\"");
            }
        }

        try buf.append(allocator, '}');
    }
    try buf.appendSlice(allocator, "]}");
    return buf.toOwnedSlice(allocator);
}

fn jsonEscapeAppend(allocator: std.mem.Allocator, list: *std.ArrayList(u8), s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try list.appendSlice(allocator, "\\\""),
            '\\' => try list.appendSlice(allocator, "\\\\"),
            '\n' => try list.appendSlice(allocator, "\\n"),
            '\r' => try list.appendSlice(allocator, "\\r"),
            '\t' => try list.appendSlice(allocator, "\\t"),
            0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F => {
                var tmp: [6]u8 = undefined;
                const encoded = try std.fmt.bufPrint(&tmp, "\\u{x:0>4}", .{c});
                try list.appendSlice(allocator, encoded);
            },
            else => try list.append(allocator, c),
        }
    }
}

/// Enhance error output with colors if not already present
pub fn enhanceGeneric(allocator: std.mem.Allocator, output: []const u8) ![]u8 {
    // Check if output already has ANSI color codes
    if (std.mem.indexOf(u8, output, "\x1b[") != null) {
        // Already has colors, return as-is
        return try allocator.dupe(u8, output);
    }

    // Output doesn't have colors, let's add them
    var result = std.ArrayList(u8).empty;
    errdefer result.deinit(allocator);

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) {
            try result.append(allocator, '\n');
            continue;
        }

        // Colorize based on content
        if (std.mem.indexOf(u8, line, "error:") != null or
            std.mem.indexOf(u8, line, "Error:") != null or
            std.mem.indexOf(u8, line, "ERROR:") != null)
        {
            // Red for error lines, try to colorize file paths separately
            try colorizeErrorLine(allocator, &result, line);
        } else if (std.mem.indexOf(u8, line, "warning:") != null or
            std.mem.indexOf(u8, line, "Warning:") != null)
        {
            // Yellow for warnings
            try result.appendSlice(allocator, Colors.yellow);
            try result.appendSlice(allocator, line);
            try result.appendSlice(allocator, Colors.reset);
        } else if (std.mem.indexOf(u8, line, "note:") != null or
            std.mem.indexOf(u8, line, "Note:") != null)
        {
            // Cyan for notes
            try result.appendSlice(allocator, Colors.cyan);
            try result.appendSlice(allocator, line);
            try result.appendSlice(allocator, Colors.reset);
        } else if (std.mem.indexOf(u8, line, "stderr") != null) {
            // Gray for stderr notices
            try result.appendSlice(allocator, Colors.gray);
            try result.appendSlice(allocator, line);
            try result.appendSlice(allocator, Colors.reset);
        } else if (std.mem.startsWith(u8, line, "   ") or
            std.mem.startsWith(u8, line, "  ") or
            std.mem.indexOf(u8, line, "^") != null)
        {
            // Dim for indented context lines and caret lines
            try result.appendSlice(allocator, Colors.gray);
            try result.appendSlice(allocator, line);
            try result.appendSlice(allocator, Colors.reset);
        } else if (std.mem.indexOf(u8, line, "+- ") != null) {
            // Cyan for build tree structure
            try result.appendSlice(allocator, Colors.cyan);
            try result.appendSlice(allocator, line);
            try result.appendSlice(allocator, Colors.reset);
        } else {
            // Normal output
            try result.appendSlice(allocator, line);
        }
        try result.append(allocator, '\n');
    }

    return result.toOwnedSlice(allocator);
}

/// Colorize an error line, highlighting file paths in cyan and errors in red
fn colorizeErrorLine(allocator: std.mem.Allocator, result: *std.ArrayList(u8), line: []const u8) !void {
    // Look for pattern: "filepath:line:col: error: message"
    if (std.mem.indexOf(u8, line, ":")) |first_colon| {
        // Check if this looks like a file path (before error:)
        if (std.mem.indexOf(u8, line, " error:")) |error_pos| {
            if (first_colon < error_pos) {
                // File path part (cyan)
                try result.*.appendSlice(allocator, Colors.cyan);
                try result.*.appendSlice(allocator, line[0..error_pos]);
                try result.*.appendSlice(allocator, Colors.reset);

                // Error part (red)
                try result.*.appendSlice(allocator, Colors.red);
                try result.*.appendSlice(allocator, line[error_pos..]);
                try result.*.appendSlice(allocator, Colors.reset);
                return;
            }
        }
    }

    // Fallback: just make the whole line red
    try result.*.appendSlice(allocator, Colors.red);
    try result.*.appendSlice(allocator, line);
    try result.*.appendSlice(allocator, Colors.reset);
}

/// Helper to get a single line from a file without loading the whole file every time
pub fn getLineFromFile(allocator: std.mem.Allocator, file_path: []const u8, line_num: u32) !?[]const u8 {
    const source = std.fs.cwd().readFileAlloc(allocator, file_path, 10 * 1024 * 1024) catch return null;
    defer allocator.free(source);

    var it = std.mem.splitScalar(u8, source, '\n');
    var current: u32 = 1;
    while (it.next()) |line| {
        if (current == line_num) return allocator.dupe(u8, line) catch null;
        current += 1;
    }
    return null;
}

pub fn formatOxlint(allocator: std.mem.Allocator, diagnostics: []const Builder.Diagnostic) ![]u8 {
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(allocator);

    const w = buf.writer(allocator);

    for (diagnostics) |d| {
        const kind_symbol = switch (d.kind) {
            // .@"error" => Colors.red ++ "✖" ++ Colors.reset,
            .@"error" => Colors.red ++ "" ++ Colors.reset,
            // .warning => Colors.yellow ++ "⚠" ++ Colors.reset,
            .warning => Colors.yellow ++ "" ++ Colors.reset,
            // .note => Colors.cyan ++ "ℹ" ++ Colors.reset,
            .note => Colors.cyan ++ "" ++ Colors.reset,
        };
        const kind_text = switch (d.kind) {
            .@"error" => Colors.red ++ Colors.bold ++ "error" ++ Colors.reset,
            .warning => Colors.yellow ++ Colors.bold ++ "warning" ++ Colors.reset,
            .note => Colors.cyan ++ Colors.bold ++ "note" ++ Colors.reset,
        };

        // Header: Icon kind: message
        try w.print("  {s} {s}: {s}\n", .{ kind_symbol, kind_text, d.message });

        // File path line: ╭─[path:line:col]
        try w.print("     {s}╭─{s}[{s}{s}:{d}:{d}{s}]\n", .{
            Colors.gray,
            Colors.reset,
            Colors.cyan,
            d.file,
            d.line,
            d.col,
            Colors.reset,
        });

        // Try to get source lines
        var source_line: ?[]const u8 = d.source_line;
        var caret_line: ?[]const u8 = d.caret_line;

        var owned_source = false;
        var owned_caret = false;

        if (source_line == null) {
            source_line = getLineFromFile(allocator, d.file, d.line) catch null;
            if (source_line != null) owned_source = true;
        }

        if (caret_line == null and d.col > 0) {
            // Generate basic caret if col is available
            var cl = std.ArrayList(u8).empty;
            for (0..d.col - 1) |_| try cl.append(allocator, ' ');
            try cl.append(allocator, '^');
            caret_line = cl.toOwnedSlice(allocator) catch null;
            if (caret_line != null) owned_caret = true;
        }

        defer {
            if (owned_source) if (source_line) |sl| allocator.free(sl);
            if (owned_caret) if (caret_line) |cl| allocator.free(cl);
        }

        if (source_line) |sl| {
            // Show line content
            const trimmed_sl = std.mem.trimLeft(u8, sl, " \t");
            const leading_spaces = sl.len - trimmed_sl.len;

            // Use faint (DIM) for line numbers to simulate smaller font
            try w.print(" \x1b[2m{s}{d: >3} │{s} {s}\n", .{ Colors.gray, d.line, Colors.reset, trimmed_sl });

            if (caret_line) |cl| {
                const trimmed_cl = if (cl.len > leading_spaces) cl[leading_spaces..] else cl;
                // Dot should be exactly the same color and weight as the vertical line separator
                try w.print("     \x1b[2m{s}·{s} {s}{s}{s}\n", .{ Colors.gray, Colors.reset, Colors.purple, trimmed_cl, Colors.reset });
            }
        }

        // Footer: ╰────
        try w.print("     {s}╰────{s}\n\n", .{ Colors.gray, Colors.reset });
    }

    return try allocator.dupe(u8, buf.items);
}
