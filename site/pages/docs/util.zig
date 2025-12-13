/// Helper function to find minimum indentation in non-empty lines
pub fn findMinIndent(lines: []const []const u8, first_non_empty: usize, last_non_empty: usize) usize {
    var min_indent: usize = std.math.maxInt(usize);
    for (lines[first_non_empty .. last_non_empty + 1]) |line| {
        if (std.mem.trim(u8, line, " \t").len > 0) {
            var indent: usize = 0;
            for (line) |char| {
                if (char == ' ' or char == '\t') {
                    indent += 1;
                } else {
                    break;
                }
            }
            if (indent < min_indent) {
                min_indent = indent;
            }
        }
    }
    return if (min_indent == std.math.maxInt(usize)) 0 else min_indent;
}

/// Helper function to remove common leading indentation
pub fn removeCommonIndentation(allocator: zx.Allocator, content: []const u8) []const u8 {
    var lines = std.array_list.Managed([]const u8).init(allocator);
    defer lines.deinit();

    var it = std.mem.splitScalar(u8, content, '\n');
    while (it.next()) |line| {
        lines.append(line) catch unreachable;
    }

    if (lines.items.len == 0) {
        return allocator.dupe(u8, "") catch unreachable;
    }

    // Find first and last non-empty lines
    var first_non_empty: ?usize = null;
    var last_non_empty: ?usize = null;
    for (lines.items, 0..) |line, i| {
        if (std.mem.trim(u8, line, " \t").len > 0) {
            if (first_non_empty == null) {
                first_non_empty = i;
            }
            last_non_empty = i;
        }
    }

    if (first_non_empty == null) {
        return allocator.dupe(u8, "") catch unreachable;
    }

    const first = first_non_empty.?;
    const last = last_non_empty.?;

    // Find minimum indentation
    const min_indent = findMinIndent(lines.items, first, last);

    // Build result with indentation removed
    var result = std.array_list.Managed(u8).init(allocator);
    defer result.deinit();

    for (lines.items[first .. last + 1], 0..) |line, i| {
        if (i > 0) {
            result.append('\n') catch unreachable;
        }
        if (std.mem.trim(u8, line, " \t").len > 0) {
            const start = @min(min_indent, line.len);
            result.appendSlice(line[start..]) catch unreachable;
        } else {
            result.appendSlice(line) catch unreachable;
        }
    }

    return allocator.dupe(u8, result.items) catch unreachable;
}

/// Extract content inside return (...) for ZX code
pub fn extractZxReturnContent(allocator: zx.Allocator, content: []const u8) []const u8 {
    const return_pattern = "return (";
    if (std.mem.indexOf(u8, content, return_pattern)) |start_idx| {
        var depth: usize = 1;
        var i = start_idx + return_pattern.len;
        while (i < content.len and depth > 0) {
            if (content[i] == '(') {
                depth += 1;
            } else if (content[i] == ')') {
                depth -= 1;
                if (depth == 0) {
                    return allocator.dupe(u8, content[start_idx + return_pattern.len .. i]) catch unreachable;
                }
            }
            i += 1;
        }
    }
    return allocator.dupe(u8, content) catch unreachable;
}

/// Extract content after return statement for Zig code (until semicolon)
pub fn extractZigReturnContent(allocator: zx.Allocator, content: []const u8) []const u8 {
    const return_pattern = "return ";
    if (std.mem.indexOf(u8, content, return_pattern)) |start_idx| {
        var depth: usize = 0;
        var in_string = false;
        var string_char: ?u8 = null;
        var i = start_idx + return_pattern.len;

        while (i < content.len) {
            const char = content[i];

            // Handle string literals
            if (char == '"' or char == '\'') {
                // Check if previous character is not a backslash (or if backslash is escaped)
                var is_escaped = false;
                if (i > start_idx + return_pattern.len) {
                    var backslash_count: usize = 0;
                    var j = i - 1;
                    while (j >= start_idx + return_pattern.len and content[j] == '\\') {
                        backslash_count += 1;
                        j -= 1;
                    }
                    is_escaped = (backslash_count % 2) == 1;
                }

                if (!is_escaped) {
                    if (!in_string) {
                        in_string = true;
                        string_char = char;
                    } else if (char == string_char) {
                        in_string = false;
                        string_char = null;
                    }
                }
            }

            // Only process brackets/braces/parentheses outside of strings
            if (!in_string) {
                if (char == '(' or char == '{' or char == '[') {
                    depth += 1;
                } else if (char == ')' or char == '}' or char == ']') {
                    depth -= 1;
                } else if (char == ';' and depth == 0) {
                    return allocator.dupe(u8, content[start_idx + return_pattern.len .. i]) catch unreachable;
                }
            }

            i += 1;
        }
    }
    return allocator.dupe(u8, content) catch unreachable;
}

const zx = @import("zx");
const std = @import("std");
const builtin = @import("builtin");
const ts = @import("tree_sitter");
const hl_query = @embedFile("../highlights.scm");
const ts_zx = @import("tree_sitter_zx");

// Cache for tree-sitter objects to avoid recreating them on every call
const HighlightCache = struct {
    parser: *ts.Parser,
    language: *const ts.Language,
    query: *ts.Query,
    mutex: std.Thread.Mutex = .{},

    var instance: ?*HighlightCache = null;

    fn getOrInit(allocator: std.mem.Allocator) !*HighlightCache {
        if (instance) |cache| return cache;

        const parser = ts.Parser.create();
        const lang: *const ts.Language = @ptrCast(ts_zx.language());

        var error_offset: u32 = 0;
        const query = ts.Query.create(@ptrCast(lang), hl_query, &error_offset) catch |err| {
            std.debug.print("Query error at offset {d}: {}\n", .{ error_offset, err });
            parser.destroy();
            lang.destroy();
            return err;
        };

        try parser.setLanguage(lang);

        const cache = try allocator.create(HighlightCache);
        cache.* = .{
            .parser = parser,
            .language = lang,
            .query = query,
        };

        instance = cache;
        std.log.info("\x1b[1;32m[HL CACHE] Initialized (this should only happen once)\x1b[0m", .{});
        return cache;
    }
};

pub fn highlightZx(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    if (builtin.os.tag == .freestanding) return try allocator.dupe(u8, source);

    var total_timer = try std.time.Timer.start();

    // Get cached objects (first call initializes, subsequent calls reuse)
    var timer = try std.time.Timer.start();
    const cache = try HighlightCache.getOrInit(std.heap.page_allocator);
    logTiming("Cache lookup/init", timer.lap());

    // Lock for thread safety (important in concurrent requests)
    cache.mutex.lock();
    defer cache.mutex.unlock();

    timer.reset();
    const tree = cache.parser.parseString(source, null) orelse return error.ParseError;
    defer tree.destroy();
    logTimingFmt("Parse source ({d} bytes)", .{source.len}, timer.lap());

    timer.reset();
    const cursor = ts.QueryCursor.create();
    defer cursor.destroy();
    cursor.exec(cache.query, tree.rootNode());
    logTiming("Query execution", timer.lap());
    timer.reset();
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();

    var last: usize = 0;
    var match_count: usize = 0;

    while (cursor.nextMatch()) |match| {
        match_count += 1;
        for (match.captures) |cap| {
            const start = cap.node.startByte();
            const end = cap.node.endByte();

            // Skip if this capture overlaps with already processed text
            if (start < last) continue;

            const capture_name = cache.query.captureNameForId(cap.index) orelse continue;

            // Copy text before this token (HTML escaped, preserving newlines)
            try appendHtmlEscapedPreserveWhitespace(&out, source[last..start]);

            // Convert dots to spaces for space-separated CSS classes
            try out.appendSlice("<span class='");
            for (capture_name) |c| {
                if (c == '.') {
                    try out.append(' ');
                } else {
                    try out.append(c);
                }
            }
            try out.appendSlice("'>");
            try appendHtmlEscapedPreserveWhitespace(&out, source[start..end]);
            try out.appendSlice("</span>");

            last = end;
        }
    }

    // Append remaining text (HTML escaped, preserving newlines)
    try appendHtmlEscapedPreserveWhitespace(&out, source[last..]);

    const result = try out.toOwnedSlice();
    logTimingFmt("HTML generation ({d} matches, {d} -> {d} bytes)", .{ match_count, source.len, result.len }, timer.lap());

    const total_elapsed = total_timer.read();
    logTiming("TOTAL highlightZx", total_elapsed);

    // var aw = std.Io.Writer.Allocating.init(allocator);
    // try tree.rootNode().format(&aw.writer);
    // return aw.written();
    //
    // var walker = tree.walk();
    // while (true) {
    //     const node = walker.node();
    //     std.log.info("{s}", .{node.kind()});
    //     if (node.desce() == null) break;
    // }
    return result;
}

fn appendHtmlEscapedPreserveWhitespace(out: *std.array_list.Managed(u8), text: []const u8) !void {
    for (text) |c| {
        switch (c) {
            '<' => try out.appendSlice("&lt;"),
            '>' => try out.appendSlice("&gt;"),
            '&' => try out.appendSlice("&amp;"),
            '"' => try out.appendSlice("&quot;"),
            '\'' => try out.appendSlice("&#39;"),
            // Preserve newlines, spaces, and tabs
            '\n', '\r', '\t', ' ' => try out.append(c),
            else => try out.append(c),
        }
    }
}

fn logTiming(comptime label: []const u8, elapsed_ns: u64) void {
    const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(std.time.ns_per_ms));
    const color_reset = "\x1b[0m";
    const color_label = "\x1b[1;35m"; // magenta
    const color_time = if (elapsed_ms < 1) "\x1b[1;32m" else if (elapsed_ms < 10) "\x1b[1;33m" else "\x1b[1;31m";
    std.log.info("  {s}[HL]{s} {s}: {s}{d:.3}ms{s}", .{
        color_label, color_reset,
        label,       color_time,
        elapsed_ms,  color_reset,
    });
}

fn logTimingFmt(comptime label: []const u8, args: anytype, elapsed_ns: u64) void {
    const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(std.time.ns_per_ms));
    const color_reset = "\x1b[0m";
    const color_label = "\x1b[1;35m"; // magenta
    const color_time = if (elapsed_ms < 1) "\x1b[1;32m" else if (elapsed_ms < 10) "\x1b[1;33m" else "\x1b[1;31m";
    var buf: [256]u8 = undefined;
    const formatted_label = std.fmt.bufPrint(&buf, label, args) catch label;
    std.log.info("  {s}[HL]{s} {s}: {s}{d:.3}ms{s}", .{
        color_label,     color_reset,
        formatted_label, color_time,
        elapsed_ms,      color_reset,
    });
}
