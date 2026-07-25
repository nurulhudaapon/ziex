// TODO: this is a prototype implementation
const Markdown = @This();

const Writer = std.array_list.Managed(u8);

const fn_header = "pub fn _zx_md(ctx: *@import(\"zx\").ComponentCtx(struct { children: @import(\"zx\").Component })) @import(\"zx\").Component {\n";
const pg_header = "pub fn Page(ctx: *@import(\"zx\").PageContext) @import(\"zx\").Component {\n";

pub fn transpile(allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
    const effective_source = if (source.len == 0 or source[source.len - 1] != '\n') blk: {
        const buf = try allocator.alloc(u8, source.len + 1);
        @memcpy(buf[0..source.len], source);
        buf[source.len] = '\n';
        break :blk buf;
    } else source;

    const parser = ts.Parser.create();
    defer parser.destroy();
    parser.setLanguage(ts.Language.fromRaw(@import("tree_sitter_mdzx").language())) catch return error.LoadingLang;
    const tree = parser.parseString(effective_source, null) orelse return error.ParseError;
    defer tree.destroy();

    const root = tree.rootNode();
    var out = Writer.init(allocator);
    errdefer out.deinit();

    var blocks = std.ArrayList([]const u8).empty;
    defer {
        for (blocks.items) |b| allocator.free(b);
        blocks.deinit(allocator);
    }

    const child_count = root.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = root.child(i) orelse continue;
        const kind = child.kind();

        if (eql(kind, "frontmatter")) {
            try writeFrontmatter(&out, effective_source, child);
        } else if (eql(kind, "atx_heading") or
            eql(kind, "paragraph") or
            eql(kind, "thematic_break") or
            eql(kind, "fenced_code_block") or
            eql(kind, "indented_code_block") or
            eql(kind, "block_quote") or
            eql(kind, "list") or
            eql(kind, "mdzx_component") or
            eql(kind, "zx_expression_block") or
            eql(kind, "link_reference_definition"))
        {
            var buf = Writer.init(allocator);
            errdefer buf.deinit();
            try writeBlock(&buf, effective_source, child);
            if (buf.items.len > 0) {
                try blocks.append(allocator, try buf.toOwnedSlice());
            } else {
                buf.deinit();
            }
        }
    }

    if (blocks.items.len > 0) {
        try out.appendSlice(fn_header);
        if (blocks.items.len == 1) {
            const block = blocks.items[0];
            try out.appendSlice("    return (");
            try appendWithAllocator(&out, block);
            try out.appendSlice(");\n");
        } else {
            // Multiple elements: wrap in <div @allocator={ctx.allocator}>
            try out.appendSlice("    return (<div @allocator={ctx.allocator}>\n");
            for (blocks.items) |block| {
                try out.appendSlice("        ");
                try out.appendSlice(block);
                try out.append('\n');
            }
            try out.appendSlice("    </div>);\n");
        }
        try out.appendSlice("}\n");
    }

    return try out.toOwnedSlice();
}

fn writeFrontmatter(out: *Writer, source: []const u8, node: ts.Node) !void {
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const kind = child.kind();
        if (eql(kind, "zig_declaration") or
            eql(kind, "pub_const_declaration") or
            eql(kind, "const_declaration"))
        {
            try out.appendSlice(textOf(source, child));
            try out.append('\n');
        }
    }
    try out.append('\n');
}

fn writeBlock(buf: *Writer, source: []const u8, node: ts.Node) !void {
    const kind = node.kind();

    if (eql(kind, "atx_heading")) {
        try writeHeading(buf, source, node);
    } else if (eql(kind, "paragraph")) {
        try writeParagraph(buf, source, node);
    } else if (eql(kind, "thematic_break")) {
        try buf.appendSlice("<hr />");
    } else if (eql(kind, "fenced_code_block")) {
        try writeFencedCodeBlock(buf, source, node);
    } else if (eql(kind, "indented_code_block")) {
        try writeIndentedCodeBlock(buf, source, node);
    } else if (eql(kind, "block_quote")) {
        try writeBlockQuote(buf, source, node);
    } else if (eql(kind, "list")) {
        try writeList(buf, source, node);
    } else if (eql(kind, "mdzx_component") or eql(kind, "zx_expression_block")) {
        try buf.appendSlice(std.mem.trim(u8, textOf(source, node), "\n \t"));
    } else if (eql(kind, "link_reference_definition")) {
        // Skip
    }
}

fn writeHeading(buf: *Writer, source: []const u8, node: ts.Node) !void {
    const level = getHeadingLevel(node);
    const tag = switch (level) {
        1 => "h1",
        2 => "h2",
        3 => "h3",
        4 => "h4",
        5 => "h5",
        6 => "h6",
        else => "h1",
    };

    try buf.append('<');
    try buf.appendSlice(tag);
    try buf.append('>');

    const content = node.childByFieldName("heading_content");
    if (content) |inline_node| {
        try writeInline(buf, source, inline_node);
    }

    try buf.appendSlice("</");
    try buf.appendSlice(tag);
    try buf.append('>');
}

fn getHeadingLevel(node: ts.Node) u8 {
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const kind = child.kind();
        if (eql(kind, "atx_h1_marker")) return 1;
        if (eql(kind, "atx_h2_marker")) return 2;
        if (eql(kind, "atx_h3_marker")) return 3;
        if (eql(kind, "atx_h4_marker")) return 4;
        if (eql(kind, "atx_h5_marker")) return 5;
        if (eql(kind, "atx_h6_marker")) return 6;
    }
    return 1;
}

fn writeParagraph(buf: *Writer, source: []const u8, node: ts.Node) !void {
    try buf.appendSlice("<p>");
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        if (eql(child.kind(), "inline")) {
            try writeInline(buf, source, child);
        }
    }
    try buf.appendSlice("</p>");
}

fn writeFencedCodeBlock(buf: *Writer, source: []const u8, node: ts.Node) !void {
    var lang: ?[]const u8 = null;
    var content: ?[]const u8 = null;

    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const kind = child.kind();
        if (eql(kind, "info_string")) {
            const info_children = child.childCount();
            var j: u32 = 0;
            while (j < info_children) : (j += 1) {
                const info_child = child.child(j) orelse continue;
                if (eql(info_child.kind(), "language")) {
                    lang = std.mem.trim(u8, textOf(source, info_child), " \t\n");
                    break;
                }
            }
        } else if (eql(kind, "code_fence_content")) {
            content = textOf(source, child);
        }
    }

    try buf.appendSlice("<pre><code");
    if (lang) |l| {
        try buf.appendSlice(" class=\"language-");
        try buf.appendSlice(l);
        try buf.append('"');
    }
    try buf.append('>');
    if (content) |c| {
        const trimmed = std.mem.trimEnd(u8, c, "\n");
        try appendEscaped(buf, trimmed);
    }
    try buf.appendSlice("</code></pre>");
}

fn writeIndentedCodeBlock(buf: *Writer, source: []const u8, node: ts.Node) !void {
    try buf.appendSlice("<pre><code>");
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const line = textOf(source, child);
        const stripped = if (line.len >= 4 and std.mem.eql(u8, line[0..4], "    "))
            line[4..]
        else
            line;
        try appendEscaped(buf, std.mem.trimEnd(u8, stripped, "\n"));
        if (i + 1 < child_count) try buf.append('\n');
    }
    try buf.appendSlice("</code></pre>");
}

fn writeBlockQuote(buf: *Writer, source: []const u8, node: ts.Node) !void {
    try buf.appendSlice("<blockquote>");
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const kind = child.kind();
        if (!eql(kind, "block_quote_marker")) {
            const text = std.mem.trim(u8, textOf(source, child), " \t\n");
            if (text.len > 0) {
                try buf.appendSlice(text);
            }
        }
    }
    try buf.appendSlice("</blockquote>");
}

fn writeList(buf: *Writer, source: []const u8, node: ts.Node) !void {
    const is_ordered = isOrderedList(node);
    const tag = if (is_ordered) "ol" else "ul";

    try buf.append('<');
    try buf.appendSlice(tag);
    try buf.append('>');

    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        if (eql(child.kind(), "list_item")) {
            try writeListItem(buf, source, child);
        }
    }

    try buf.appendSlice("</");
    try buf.appendSlice(tag);
    try buf.append('>');
}

fn isOrderedList(node: ts.Node) bool {
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        if (eql(child.kind(), "list_item")) {
            const item_children = child.childCount();
            var j: u32 = 0;
            while (j < item_children) : (j += 1) {
                const item_child = child.child(j) orelse continue;
                const kind = item_child.kind();
                if (eql(kind, "list_marker_dot") or eql(kind, "list_marker_parenthesis")) return true;
                if (eql(kind, "list_marker_plus") or eql(kind, "list_marker_minus") or eql(kind, "list_marker_star")) return false;
            }
        }
    }
    return false;
}

fn writeListItem(buf: *Writer, source: []const u8, node: ts.Node) !void {
    try buf.appendSlice("<li>");
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const kind = child.kind();
        if (std.mem.startsWith(u8, kind, "list_marker_")) continue;
        if (eql(kind, "task_list_marker_checked")) {
            try buf.appendSlice("<input type=\"checkbox\" checked=\"\" disabled=\"\" /> ");
            continue;
        }
        if (eql(kind, "task_list_marker_unchecked")) {
            try buf.appendSlice("<input type=\"checkbox\" disabled=\"\" /> ");
            continue;
        }
        const text = std.mem.trim(u8, textOf(source, child), " \t\n");
        if (text.len > 0) {
            try buf.appendSlice(text);
        }
    }
    try buf.appendSlice("</li>");
}

fn writeInline(buf: *Writer, source: []const u8, node: ts.Node) !void {
    const child_count = node.childCount();
    if (child_count == 0) {
        // Leaf inline node (e.g., plain text with no special markdown)
        try buf.appendSlice(textOf(source, node));
        return;
    }
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        try writeInlineElement(buf, source, child);
    }
}

fn writeInlineElement(buf: *Writer, source: []const u8, node: ts.Node) !void {
    const kind = node.kind();

    if (eql(kind, "code_span")) {
        try writeCodeSpan(buf, source, node);
    } else if (eql(kind, "emphasis")) {
        try writeEmphasis(buf, source, node);
    } else if (eql(kind, "strong_emphasis")) {
        try writeStrongEmphasis(buf, source, node);
    } else if (eql(kind, "bold_italic")) {
        try writeBoldItalic(buf, source, node);
    } else if (eql(kind, "strikethrough")) {
        try writeStrikethrough(buf, source, node);
    } else if (eql(kind, "inline_link")) {
        try writeInlineLink(buf, source, node);
    } else if (eql(kind, "full_reference_link")) {
        try writeReferenceLink(buf, source, node);
    } else if (eql(kind, "image")) {
        try writeImage(buf, source, node);
    } else if (eql(kind, "autolink")) {
        try writeAutolink(buf, source, node);
    } else if (eql(kind, "backslash_escape")) {
        const text = textOf(source, node);
        if (text.len >= 2) {
            try buf.append(text[1]);
        }
    } else {
        // Anonymous nodes (raw text, whitespace) or unrecognized named nodes
        try buf.appendSlice(textOf(source, node));
    }
}

fn writeCodeSpan(buf: *Writer, source: []const u8, node: ts.Node) !void {
    try buf.appendSlice("<code>");
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        if (eql(child.kind(), "code_span_delimiter")) continue;
        if (eql(child.kind(), "code_span_content")) {
            try appendEscaped(buf, textOf(source, child));
        }
    }
    try buf.appendSlice("</code>");
}

fn writeEmphasis(buf: *Writer, source: []const u8, node: ts.Node) !void {
    try buf.appendSlice("<em>");
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        if (eql(child.kind(), "emphasis_content")) {
            try buf.appendSlice(textOf(source, child));
        }
    }
    try buf.appendSlice("</em>");
}

fn writeStrongEmphasis(buf: *Writer, source: []const u8, node: ts.Node) !void {
    try buf.appendSlice("<strong>");
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        if (eql(child.kind(), "strong_emphasis_content")) {
            try buf.appendSlice(textOf(source, child));
        }
    }
    try buf.appendSlice("</strong>");
}

fn writeBoldItalic(buf: *Writer, source: []const u8, node: ts.Node) !void {
    try buf.appendSlice("<strong><em>");
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        if (eql(child.kind(), "bold_italic_content")) {
            try buf.appendSlice(textOf(source, child));
        }
    }
    try buf.appendSlice("</em></strong>");
}

fn writeStrikethrough(buf: *Writer, source: []const u8, node: ts.Node) !void {
    try buf.appendSlice("<s>");
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        if (eql(child.kind(), "strikethrough_content")) {
            try buf.appendSlice(textOf(source, child));
        }
    }
    try buf.appendSlice("</s>");
}

fn writeInlineLink(buf: *Writer, source: []const u8, node: ts.Node) !void {
    var href: ?[]const u8 = null;
    var link_text_node: ?ts.Node = null;

    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const kind = child.kind();
        if (eql(kind, "link_text")) {
            link_text_node = child;
        } else if (eql(kind, "link_destination")) {
            href = textOf(source, child);
        }
    }

    try buf.appendSlice("<a");
    if (href) |h| {
        try buf.appendSlice(" href=\"");
        try buf.appendSlice(h);
        try buf.append('"');
    }
    try buf.append('>');
    if (link_text_node) |lt| {
        try writeLinkTextContent(buf, source, lt);
    }
    try buf.appendSlice("</a>");
}

fn writeReferenceLink(buf: *Writer, source: []const u8, node: ts.Node) !void {
    var link_text_node: ?ts.Node = null;
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        if (eql(child.kind(), "link_text")) {
            link_text_node = child;
        }
    }

    try buf.appendSlice("<a>");
    if (link_text_node) |lt| {
        try writeLinkTextContent(buf, source, lt);
    }
    try buf.appendSlice("</a>");
}

fn writeLinkTextContent(buf: *Writer, source: []const u8, node: ts.Node) !void {
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        if (!child.isNamed()) {
            const text = textOf(source, child);
            if (eql(text, "[") or eql(text, "]")) continue;
            try buf.appendSlice(text);
        } else {
            try buf.appendSlice(textOf(source, child));
        }
    }
}

fn writeImage(buf: *Writer, source: []const u8, node: ts.Node) !void {
    var src: ?[]const u8 = null;
    var alt_node: ?ts.Node = null;

    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const kind = child.kind();
        if (eql(kind, "link_text")) {
            alt_node = child;
        } else if (eql(kind, "link_destination")) {
            src = textOf(source, child);
        }
    }

    try buf.appendSlice("<img");
    if (src) |s| {
        try buf.appendSlice(" src=\"");
        try buf.appendSlice(s);
        try buf.append('"');
    }
    if (alt_node) |alt| {
        try buf.appendSlice(" alt=\"");
        try writeLinkTextContent(buf, source, alt);
        try buf.append('"');
    }
    try buf.appendSlice(" />");
}

fn writeAutolink(buf: *Writer, source: []const u8, node: ts.Node) !void {
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        if (eql(child.kind(), "uri")) {
            const uri = textOf(source, child);
            try buf.appendSlice("<a href=\"");
            try buf.appendSlice(uri);
            try buf.appendSlice("\">");
            try buf.appendSlice(uri);
            try buf.appendSlice("</a>");
            return;
        }
    }
}

/// Inject `@allocator={ctx.allocator}` into the first tag of a ZX string.
fn appendWithAllocator(out: *Writer, zx_str: []const u8) !void {
    for (zx_str, 0..) |c, idx| {
        if (c == '/' and idx + 1 < zx_str.len and zx_str[idx + 1] == '>') {
            try out.appendSlice(zx_str[0..idx]);
            try out.appendSlice(" @allocator={ctx.allocator}");
            try out.appendSlice(zx_str[idx..]);
            return;
        }
        if (c == '>') {
            try out.appendSlice(zx_str[0..idx]);
            try out.appendSlice(" @allocator={ctx.allocator}");
            try out.appendSlice(zx_str[idx..]);
            return;
        }
    }
    try out.appendSlice(zx_str);
}

fn textOf(source: []const u8, node: ts.Node) []const u8 {
    const start = node.startByte();
    const end = node.endByte();
    if (start < end and end <= source.len) {
        return source[start..end];
    }
    return "";
}

fn appendEscaped(buf: *Writer, text: []const u8) !void {
    for (text) |c| {
        switch (c) {
            '&' => try buf.appendSlice("&amp;"),
            '<' => try buf.appendSlice("&lt;"),
            '>' => try buf.appendSlice("&gt;"),
            else => try buf.append(c),
        }
    }
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

const std = @import("std");
const ts = @import("tree_sitter");
