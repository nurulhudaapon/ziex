const std = @import("std");
const ts = @import("tree_sitter");
const Parse = @import("Parse.zig");
const log = std.log.scoped(.@"zx/render");
const Ast = Parse.Ast;
const NodeKind = Parse.NodeKind;

pub const FormatContext = struct {
    indent_level: u32 = 0,
    in_block: bool = false,

    fn writeIndent(self: *FormatContext, w: *std.io.Writer) !void {
        for (0..self.indent_level * 4) |_| try w.writeAll(" ");
    }
};

pub const ExtractBlockResult = struct {
    zx_blocks: []const []const u8,
    zig_source: [:0]const u8,

    pub fn deinit(self: *ExtractBlockResult, allocator: std.mem.Allocator) void {
        for (self.zx_blocks) |block| {
            allocator.free(block);
        }
        allocator.free(self.zx_blocks);
        allocator.free(self.zig_source);
    }
};

/// Extract zx_block content and replace with placeholders for Zig formatting
pub fn extractBlocks(allocator: std.mem.Allocator, ast: *Ast) !ExtractBlockResult {
    var blocks = std.ArrayList([]const u8){};
    defer blocks.deinit(allocator);

    var cleaned_source = std.ArrayList(u8){};
    defer cleaned_source.deinit(allocator);

    const root = ast.tree.rootNode();
    try extractBlocksInner(ast, root, &blocks, &cleaned_source, allocator);

    try cleaned_source.append(allocator, 0);
    const cleaned = try allocator.dupeZ(u8, cleaned_source.items[0 .. cleaned_source.items.len - 1]);

    return ExtractBlockResult{
        .zx_blocks = try blocks.toOwnedSlice(allocator),
        .zig_source = cleaned,
    };
}

fn extractBlocksInner(
    ast: *Ast,
    node: ts.Node,
    blocks: *std.ArrayList([]const u8),
    cleaned_source: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    const start_byte = node.startByte();
    const end_byte = node.endByte();
    const node_kind = NodeKind.fromNode(node);

    // If this is a zx_block, extract it and replace with placeholder
    if (node_kind == .zx_block) {
        const block_text = ast.source[start_byte..end_byte];
        const block_copy = try allocator.dupe(u8, block_text);
        try blocks.append(allocator, block_copy);

        // Use a valid Zig identifier as placeholder
        const placeholder = try std.fmt.allocPrint(allocator, "__ZX_BLOCK_{d}__", .{blocks.items.len - 1});
        defer allocator.free(placeholder);
        try cleaned_source.appendSlice(allocator, placeholder);
        return;
    }

    // For other nodes, recursively process children
    const child_count = node.childCount();
    if (child_count == 0) {
        // Leaf node - copy source text
        if (start_byte < end_byte and end_byte <= ast.source.len) {
            try cleaned_source.appendSlice(allocator, ast.source[start_byte..end_byte]);
        }
        return;
    }

    // Process children with gaps
    var current_pos = start_byte;
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_start = child.startByte();
        const child_end = child.endByte();

        // Copy gap before child
        if (current_pos < child_start and child_start <= ast.source.len) {
            try cleaned_source.appendSlice(allocator, ast.source[current_pos..child_start]);
        }

        // Process child
        try extractBlocksInner(ast, child, blocks, cleaned_source, allocator);
        current_pos = child_end;
    }

    // Copy remaining gap after last child
    if (current_pos < end_byte and end_byte <= ast.source.len) {
        try cleaned_source.appendSlice(allocator, ast.source[current_pos..end_byte]);
    }
}

fn parseBlockPlaceholder(source: []const u8, start: usize) struct { index: usize, end: usize } {
    var i = start;
    if (i + 11 >= source.len or !std.mem.startsWith(u8, source[i..], "__ZX_BLOCK_")) {
        return .{ .index = 0, .end = start };
    }

    i += 11; // skip "__ZX_BLOCK_"

    // Parse number
    const num_start = i;
    while (i < source.len and std.ascii.isDigit(source[i])) {
        i += 1;
    }

    if (i == num_start) {
        return .{ .index = 0, .end = start };
    }

    const num_str = source[num_start..i];
    const block_index = std.fmt.parseInt(usize, num_str, 10) catch {
        return .{ .index = 0, .end = start };
    };

    // Expect closing "__"
    if (i + 2 > source.len or !std.mem.eql(u8, source[i .. i + 2], "__")) {
        return .{ .index = 0, .end = start };
    }

    i += 2; // skip "__"

    return .{ .index = block_index, .end = i };
}

/// Replace __ZX_BLOCK_n__ placeholders with formatted zx_block content
pub fn patchInBlocks(allocator: std.mem.Allocator, extract_result: ExtractBlockResult) ![:0]const u8 {
    var result = std.ArrayList(u8){};
    defer result.deinit(allocator);

    var i: usize = 0;
    while (i < extract_result.zig_source.len) {
        if (i + 12 < extract_result.zig_source.len and
            std.mem.startsWith(u8, extract_result.zig_source[i..], "__ZX_BLOCK_"))
        {
            const parsed = parseBlockPlaceholder(extract_result.zig_source, i);
            if (parsed.end > i and parsed.index < extract_result.zx_blocks.len) {
                const zx_block = extract_result.zx_blocks[parsed.index];

                // Calculate the indentation level where the placeholder appears
                const base_indent = getIndentationLevel(extract_result.zig_source, i);

                // Format the zx_block using the tree-sitter renderer
                var block_ast = try Parse.parse(allocator, zx_block);
                defer block_ast.deinit(allocator);

                var block_writer = std.io.Writer.Allocating.init(allocator);
                defer block_writer.deinit();
                const root = block_ast.tree.rootNode();
                var ctx = FormatContext{};
                ctx.indent_level = base_indent;
                try renderNodeWithContext(&block_ast, root, &block_writer.writer, &ctx);
                const formatted_block = block_writer.written();

                try result.appendSlice(allocator, formatted_block);
                i = parsed.end;
                continue;
            }
        }

        try result.append(allocator, extract_result.zig_source[i]);
        i += 1;
    }

    try result.append(allocator, 0);
    const result_slice = result.items[0 .. result.items.len - 1 :0];
    return try allocator.dupeZ(u8, result_slice);
}

fn getIndentationLevel(source: []const u8, pos: usize) u32 {
    // Find the start of the line containing pos
    var line_start = pos;
    while (line_start > 0 and source[line_start - 1] != '\n') {
        line_start -= 1;
    }

    // Count leading spaces/tabs
    var spaces: u32 = 0;
    var idx = line_start;
    while (idx < pos and idx < source.len) {
        if (source[idx] == ' ') {
            spaces += 1;
        } else if (source[idx] == '\t') {
            spaces += 4;
        } else {
            break;
        }
        idx += 1;
    }

    return spaces / 4;
}

pub fn renderNode(self: *Ast, node: ts.Node, w: *std.io.Writer) !void {
    // Check if this is the root node - if so, do extraction/Zig formatting/patching
    const root = self.tree.rootNode();
    const is_root = node.startByte() == root.startByte() and
        node.endByte() == root.endByte();

    if (is_root) {
        const allocator = self.allocator;

        // First extract zx_blocks and replace with placeholders
        var extract_result = try extractBlocks(allocator, self);
        defer extract_result.deinit(allocator);

        // Format the Zig code with placeholders
        var zig_ast = try std.zig.Ast.parse(allocator, extract_result.zig_source, .zig);
        defer zig_ast.deinit(allocator);

        if (zig_ast.errors.len > 0) {
            // If Zig parsing fails, fall back to direct rendering
            var ctx = FormatContext{};
            try renderNodeWithContext(self, node, w, &ctx);
            return;
        }

        const formatted_zig = try zig_ast.renderAlloc(allocator);
        defer allocator.free(formatted_zig);

        // Free old zig_source and replace with formatted
        allocator.free(extract_result.zig_source);
        extract_result.zig_source = try allocator.dupeZ(u8, formatted_zig);

        // Patch in formatted zx_blocks
        const final_result = try patchInBlocks(allocator, extract_result);
        defer allocator.free(final_result);

        try w.writeAll(final_result);
        return;
    }

    // For non-root nodes, render directly
    var ctx = FormatContext{};
    try renderNodeWithContext(self, node, w, &ctx);
}

pub fn renderNodeWithContext(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
    ctx: *FormatContext,
) anyerror!void {
    const node_kind = NodeKind.fromNode(node);

    // Track if we're entering a zx_block
    const was_in_zx_block = ctx.in_block;
    if (node_kind == .zx_block) {
        ctx.in_block = true;
    }
    defer if (node_kind == .zx_block) {
        ctx.in_block = was_in_zx_block;
    };

    // If not in zx_block, render Zig code as-is
    if (!ctx.in_block) {
        try renderSourceWithChildren(self, node, w, ctx);
        return;
    }

    // We're in zx_block - apply formatting
    switch (node_kind) {
        .zx_block => {
            try renderBlock(self, node, w, ctx);
        },
        .zx_element => {
            try renderElement(self, node, w, ctx);
        },
        .zx_self_closing_element => {
            try renderSelfClosingElement(self, node, w, ctx);
        },
        .zx_start_tag => {
            try renderStartTag(self, node, w);
        },
        .zx_end_tag => {
            try renderEndTag(self, node, w);
        },
        .zx_text => {
            try renderText(self, node, w);
        },
        .zx_child => {
            try renderChild(self, node, w, ctx);
        },
        .zx_expression_block => {
            try renderExpressionBlock(self, node, w, ctx);
        },
        else => {
            try renderSourceWithChildren(self, node, w, ctx);
        },
    }
}

/// Render the source text with recursive child handling
fn renderSourceWithChildren(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
    ctx: *FormatContext,
) !void {
    const start_byte = node.startByte();
    const end_byte = node.endByte();
    const child_count = node.childCount();

    if (child_count == 0) {
        if (start_byte < end_byte and end_byte <= self.source.len) {
            try w.writeAll(self.source[start_byte..end_byte]);
        }
        return;
    }

    var current_pos = start_byte;
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_start = child.startByte();
        const child_end = child.endByte();

        if (current_pos < child_start and child_start <= self.source.len) {
            try w.writeAll(self.source[current_pos..child_start]);
        }

        try renderNodeWithContext(self, child, w, ctx);
        current_pos = child_end;
    }

    if (current_pos < end_byte and end_byte <= self.source.len) {
        try w.writeAll(self.source[current_pos..end_byte]);
    }
}

/// Calculate source indentation level at a given byte offset
fn getSourceIndentLevel(source: []const u8, byte_offset: usize) u32 {
    // Find the start of the line containing this offset
    var line_start = byte_offset;
    while (line_start > 0 and source[line_start - 1] != '\n') {
        line_start -= 1;
    }

    // Count leading spaces
    var spaces: u32 = 0;
    var pos = line_start;
    while (pos < byte_offset and pos < source.len) {
        if (source[pos] == ' ') {
            spaces += 1;
        } else if (source[pos] == '\t') {
            spaces += 4;
        } else {
            break;
        }
        pos += 1;
    }

    return spaces / 4;
}

/// Render zx_block: ( <element> )
fn renderBlock(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
    ctx: *FormatContext,
) !void {
    const child_count = node.childCount();
    var element_node: ?ts.Node = null;

    // Find the main element inside the block
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_kind = NodeKind.fromNode(child);
        switch (child_kind) {
            .zx_element, .zx_self_closing_element, .zx_fragment => {
                element_node = child;
                break;
            },
            else => {},
        }
    }

    // Use the context's indent level as the base (set by patchInZxBlocks)
    const base_indent = ctx.indent_level;

    try w.writeAll("(");

    if (element_node) |elem| {
        // Check if element is multiline (has newlines in source)
        const elem_start = elem.startByte();
        const elem_end = elem.endByte();
        const is_multiline = if (elem_start < elem_end and elem_end <= self.source.len)
            std.mem.indexOf(u8, self.source[elem_start..elem_end], "\n") != null
        else
            false;

        if (is_multiline) {
            try w.writeAll("\n");
            // Set indent to base + 1 for the element
            ctx.indent_level = base_indent + 1;
            try ctx.writeIndent(w);
            try renderNodeWithContext(self, elem, w, ctx);
            // Closing paren at base indent level
            ctx.indent_level = base_indent;
            try w.writeAll("\n");
            try ctx.writeIndent(w);
        } else {
            try renderNodeWithContext(self, elem, w, ctx);
        }
    }

    try w.writeAll(")");
}

/// Render zx_element: <tag>content</tag>
fn renderElement(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
    ctx: *FormatContext,
) !void {
    const child_count = node.childCount();
    var start_tag_node: ?ts.Node = null;
    var end_tag_node: ?ts.Node = null;
    var content_nodes = std.ArrayList(ts.Node){};
    defer content_nodes.deinit(self.allocator);

    // Collect all parts
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_kind = NodeKind.fromNode(child);
        if (child_kind == .zx_start_tag) {
            start_tag_node = child;
        } else if (child_kind == .zx_end_tag) {
            end_tag_node = child;
        } else {
            try content_nodes.append(self.allocator, child);
        }
    }

    // Render start tag
    if (start_tag_node) |st| {
        try renderStartTag(self, st, w);
    }

    // - If there's whitespace/newline between start tag and first content -> vertical
    // - Otherwise -> horizontal
    const has_meaningful_content = blk: {
        for (content_nodes.items) |child| {
            const child_kind = NodeKind.fromNode(child);
            if (child_kind == .zx_child) {
                // Check if zx_child has meaningful content
                const cc = child.childCount();
                var j: u32 = 0;
                while (j < cc) : (j += 1) {
                    const gc = child.child(j) orelse continue;
                    const gck = NodeKind.fromNode(gc);
                    if (gck == .zx_text) {
                        const text = self.source[gc.startByte()..gc.endByte()];
                        if (std.mem.trim(u8, text, &std.ascii.whitespace).len > 0) {
                            break :blk true;
                        }
                    } else {
                        break :blk true;
                    }
                }
            }
        }
        break :blk false;
    };

    const is_vertical = blk: {
        if (!has_meaningful_content) break :blk false;

        // Check whitespace between start tag end and first content
        const start_tag_end = if (start_tag_node) |st| st.endByte() else node.startByte();
        for (content_nodes.items) |child| {
            const child_start = child.startByte();
            if (start_tag_end < child_start and child_start <= self.source.len) {
                const between = self.source[start_tag_end..child_start];
                // If there's a newline, it's vertical
                if (std.mem.indexOf(u8, between, "\n") != null) {
                    break :blk true;
                }
            }
            break;
        }
        break :blk false;
    };

    if (is_vertical) {
        ctx.indent_level += 1;
    }

    // Render content - skip whitespace-only children
    var rendered_any = false;
    for (content_nodes.items) |child| {
        const child_kind = NodeKind.fromNode(child);
        if (child_kind == .zx_child) {
            // Check if child has meaningful content
            if (!hasMeaningfulContent(self, child)) continue;

            // Check if this child should be on a new line
            if (is_vertical) {
                try w.writeAll("\n");
                try ctx.writeIndent(w);
            }
            try renderChild(self, child, w, ctx);
            rendered_any = true;
        } else {
            try renderNodeWithContext(self, child, w, ctx);
            rendered_any = true;
        }
    }

    if (is_vertical and rendered_any) {
        ctx.indent_level -= 1;
        try w.writeAll("\n");
        try ctx.writeIndent(w);
    } else if (is_vertical) {
        ctx.indent_level -= 1;
    }

    // Render end tag
    if (end_tag_node) |et| {
        try renderEndTag(self, et, w);
    }
}

/// Render self-closing element: <Tag attr="value" />
fn renderSelfClosingElement(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
    ctx: *FormatContext,
) !void {
    _ = ctx;
    try w.writeAll("<");

    // Tag name
    const tag_name_node = node.childByFieldName("name");
    if (tag_name_node) |name_node| {
        const tag_name_text = try self.getNodeText(name_node);
        try w.writeAll(tag_name_text);
    }

    // Attributes
    try renderAttributesFromNode(self, node, w);

    try w.writeAll(" />");
}

/// Render start tag: <tag attrs>
fn renderStartTag(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
) !void {
    try w.writeAll("<");

    // Tag name
    const tag_name_node = node.childByFieldName("name");
    if (tag_name_node) |name_node| {
        const tag_name_text = try self.getNodeText(name_node);
        try w.writeAll(tag_name_text);
    }

    // Attributes
    try renderAttributesFromNode(self, node, w);

    try w.writeAll(">");
}

/// Render end tag: </tag>
fn renderEndTag(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
) !void {
    try w.writeAll("</");

    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_kind = NodeKind.fromNode(child);
        if (child_kind == .zx_tag_name) {
            const tag_name = try self.getNodeText(child);
            try w.writeAll(tag_name);
            break;
        }
    }

    try w.writeAll(">");
}

/// Render text content
/// Collapses multiple consecutive whitespace to a single space while
/// preserving leading/trailing single spaces (for inline text with expressions)
fn renderText(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
) !void {
    const start_byte = node.startByte();
    const end_byte = node.endByte();
    if (start_byte >= end_byte or end_byte > self.source.len) return;

    const text = self.source[start_byte..end_byte];
    const trimmed = std.mem.trim(u8, text, &std.ascii.whitespace);
    if (trimmed.len == 0) return;

    const has_leading_ws = text.len > 0 and std.ascii.isWhitespace(text[0]);
    const has_trailing_ws = text.len > 0 and std.ascii.isWhitespace(text[text.len - 1]);

    // Write leading space if there was leading whitespace
    if (has_leading_ws) {
        try w.writeAll(" ");
    }

    // Write the trimmed content (no internal whitespace normalization for now)
    try w.writeAll(trimmed);

    // Write trailing space if there was trailing whitespace
    if (has_trailing_ws) {
        try w.writeAll(" ");
    }
}

/// Check if a child node has meaningful (non-whitespace) content
fn hasMeaningfulContent(self: *Ast, node: ts.Node) bool {
    const child_count = node.childCount();
    if (child_count == 0) return false;

    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_kind = NodeKind.fromNode(child);
        if (child_kind == .zx_text) {
            const text = self.getNodeText(child) catch continue;
            if (std.mem.trim(u8, text, &std.ascii.whitespace).len > 0) {
                return true;
            }
        } else {
            return true;
        }
    }
    return false;
}

/// Render zx_child node
fn renderChild(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
    ctx: *FormatContext,
) !void {
    const child_count = node.childCount();
    if (child_count == 0) return;

    if (!hasMeaningfulContent(self, node)) return;

    // Render children
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        try renderNodeWithContext(self, child, w, ctx);
    }
}

/// Render expression block: {expr} or control flow
fn renderExpressionBlock(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
    ctx: *FormatContext,
) anyerror!void {
    const child_count = node.childCount();

    // Check for control flow expressions
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_kind = NodeKind.fromNode(child);

        switch (child_kind) {
            .if_expression => {
                try renderIfExpression(self, child, w, ctx);
                return;
            },
            .for_expression => {
                try renderForExpression(self, child, w, ctx);
                return;
            },
            .while_expression => {
                try renderWhileExpression(self, child, w, ctx);
                return;
            },
            .switch_expression => {
                try renderSwitchExpression(self, child, w, ctx);
                return;
            },
            else => {},
        }
    }

    // Simple expression - render source as-is (keeps original braces and format)
    const start_byte = node.startByte();
    const end_byte = node.endByte();
    if (start_byte < end_byte and end_byte <= self.source.len) {
        const text = self.source[start_byte..end_byte];
        // Normalize whitespace in simple expressions
        const trimmed = std.mem.trim(u8, text, &std.ascii.whitespace);
        try w.writeAll(trimmed);
    }
}

/// Render if expression: {if (cond) (<then>) else (<else>)}
fn renderIfExpression(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
    ctx: *FormatContext,
) !void {
    var condition_node: ?ts.Node = null;
    var then_node: ?ts.Node = null;
    var else_node: ?ts.Node = null;

    const child_count = node.childCount();
    var zx_block_count: u32 = 0;

    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        condition_node = node.childByFieldName("condition");

        const child_kind = NodeKind.fromNode(child);
        if (child_kind == .zx_block or child_kind == .parenthesized_expression) {
            if (zx_block_count == 0) {
                then_node = child;
            } else if (zx_block_count == 1) {
                else_node = child;
            }
            zx_block_count += 1;
        }
    }

    try w.writeAll("{if ");

    // Condition
    if (condition_node) |cond| {
        const cond_text = try self.getNodeText(cond);
        const trimmed = std.mem.trim(u8, cond_text, &std.ascii.whitespace);
        if (trimmed.len > 0 and trimmed[0] != '(') {
            try w.writeAll("(");
            try w.writeAll(trimmed);
            try w.writeAll(")");
        } else {
            try w.writeAll(trimmed);
        }
    }

    try w.writeAll(" ");

    ctx.indent_level -= 1;
    // Then branch
    if (then_node) |then_b| {
        const then_kind = NodeKind.fromNode(then_b);
        switch (then_kind) {
            .zx_block => {
                try renderBlockInline(self, then_b, w, ctx);
            },
            .parenthesized_expression => {
                try w.writeAll(try self.getNodeText(then_b));
            },
            else => {},
        }
    }

    // Else branch
    if (else_node) |else_b| {
        try w.writeAll(" else ");
        const else_kind = NodeKind.fromNode(else_b);
        switch (else_kind) {
            .zx_block => {
                try renderBlockInline(self, else_b, w, ctx);
            },
            .parenthesized_expression => {
                try w.writeAll(try self.getNodeText(else_b));
            },
            else => {},
        }
    }

    try w.writeAll("}");
    ctx.indent_level += 1;
}

/// Render for expression: {for (items) |item| (<body>)}
fn renderForExpression(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
    ctx: *FormatContext,
) !void {
    var iterable_node: ?ts.Node = null;
    var payload_node: ?ts.Node = null;
    var body_node: ?ts.Node = null;

    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_kind = NodeKind.fromNode(child);

        switch (child_kind) {
            .identifier, .field_expression => {
                if (iterable_node == null) {
                    iterable_node = child;
                }
            },
            .payload => {
                payload_node = child;
            },
            .zx_block, .parenthesized_expression => {
                body_node = child;
            },
            else => {},
        }
    }

    try w.writeAll("{for (");

    if (iterable_node) |it| {
        const it_text = try self.getNodeText(it);
        try w.writeAll(it_text);
    }

    try w.writeAll(") ");

    if (payload_node) |pay| {
        const pay_text = try self.getNodeText(pay);
        try w.writeAll(pay_text);
    }

    try w.writeAll(" ");

    if (body_node) |body| {
        const body_kind = NodeKind.fromNode(body);
        ctx.indent_level -= 1;
        switch (body_kind) {
            .zx_block => {
                try renderBlockInline(self, body, w, ctx);
            },
            .parenthesized_expression => {
                try renderExpressionBlock(self, body, w, ctx);
            },
            else => {},
        }
        ctx.indent_level += 1;
    }

    try w.writeAll("}");
}

/// Render while expression: {while (cond) : (continue_expr) (<body>)}
fn renderWhileExpression(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
    ctx: *FormatContext,
) !void {
    var condition_node: ?ts.Node = null;
    var continue_node: ?ts.Node = null;
    var body_node: ?ts.Node = null;

    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        condition_node = node.childByFieldName("condition");

        const child_kind = NodeKind.fromNode(child);
        switch (child_kind) {
            .assignment_expression => {
                continue_node = child;
            },
            .zx_block => {
                body_node = child;
            },
            else => {},
        }
    }

    try w.writeAll("{while (");

    // Condition
    if (condition_node) |cond| {
        const cond_text = try self.getNodeText(cond);
        try w.writeAll(std.mem.trim(u8, cond_text, &std.ascii.whitespace));
    }

    try w.writeAll(")");

    // Continue expression (optional)
    if (continue_node) |cont| {
        try w.writeAll(" : (");
        const cont_text = try self.getNodeText(cont);
        try w.writeAll(std.mem.trim(u8, cont_text, &std.ascii.whitespace));
        try w.writeAll(")");
    }

    try w.writeAll(" ");

    // Body
    if (body_node) |body| {
        ctx.indent_level -= 1;
        try renderBlockInline(self, body, w, ctx);
        ctx.indent_level += 1;
    }

    try w.writeAll("}");
}

/// Render switch expression: {switch (val) { .case => (<body>), ... }}
fn renderSwitchExpression(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
    ctx: *FormatContext,
) !void {
    var switch_expr_node: ?ts.Node = null;
    var cases = std.ArrayList(struct { pattern: []const u8, value: ts.Node }){};
    defer cases.deinit(self.allocator);

    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_kind = NodeKind.fromNode(child);

        switch (child_kind) {
            .identifier, .field_expression => {
                switch_expr_node = child;
            },
            .switch_case => {
                var pattern_node: ?ts.Node = null;
                var value_node: ?ts.Node = null;

                const case_child_count = child.childCount();
                var j: u32 = 0;
                while (j < case_child_count) : (j += 1) {
                    const case_child = child.child(j) orelse continue;
                    const case_child_kind = NodeKind.fromNode(case_child);

                    switch (case_child_kind) {
                        .zx_block, .parenthesized_expression, .for_expression, .while_expression, .switch_expression, .if_expression => {
                            value_node = case_child;
                        },
                        else => {
                            if (pattern_node == null and case_child.childCount() > 0) {
                                pattern_node = case_child;
                            }
                        },
                    }
                }

                if (pattern_node) |p| {
                    const pattern_text = try self.getNodeText(p);
                    if (value_node) |v| {
                        try cases.append(self.allocator, .{
                            .pattern = pattern_text,
                            .value = v,
                        });
                    }
                }
            },
            else => {},
        }
    }

    try w.writeAll("{switch (");

    if (switch_expr_node) |expr| {
        const expr_text = try self.getNodeText(expr);
        try w.writeAll(expr_text);
    }

    try w.writeAll(") {");

    for (cases.items) |case| {
        try w.writeAll("\n");
        ctx.indent_level += 1;
        try ctx.writeIndent(w);
        ctx.indent_level -= 1;
        try w.writeAll(std.mem.trim(u8, case.pattern, &std.ascii.whitespace));
        try w.writeAll(" => ");
        const case_value_kind = NodeKind.fromNode(case.value);
        switch (case_value_kind) {
            .zx_block => {
                try renderBlockInline(self, case.value, w, ctx);
            },
            .parenthesized_expression => {
                try w.writeAll(try self.getNodeText(case.value));
            },
            .for_expression, .while_expression, .switch_expression, .if_expression => {
                try renderExpressionBlock(self, case.value, w, ctx);
            },
            else => {},
        }
        try w.writeAll(",");
    }

    try w.writeAll("\n");
    try ctx.writeIndent(w);
    try w.writeAll("}}");
}

/// Render zx_block inline (for use in control flow expressions)
fn renderBlockInline(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
    ctx: *FormatContext,
) !void {
    const child_count = node.childCount();
    var element_node: ?ts.Node = null;

    // Find the main element
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_kind = NodeKind.fromNode(child);
        switch (child_kind) {
            .zx_element, .zx_self_closing_element, .zx_fragment => {
                element_node = child;
                break;
            },
            else => {},
        }
    }

    try w.writeAll("(");

    if (element_node) |elem| {
        // Check if element is multiline
        const elem_start = elem.startByte();
        const elem_end = elem.endByte();
        const is_multiline = if (elem_start < elem_end and elem_end <= self.source.len)
            std.mem.indexOf(u8, self.source[elem_start..elem_end], "\n") != null
        else
            false;

        if (is_multiline) {
            try w.writeAll("\n");
            ctx.indent_level += 2;
            try ctx.writeIndent(w);
            try renderNodeWithContext(self, elem, w, ctx);
            ctx.indent_level -= 2;
            try w.writeAll("\n");
            ctx.indent_level += 1;
            try ctx.writeIndent(w);
            try w.writeAll(")");
            ctx.indent_level -= 1;
        } else {
            try renderNodeWithContext(self, elem, w, ctx);
            try w.writeAll(")");
        }
    }
}

/// Render attributes from a node (start tag or self-closing element)
fn renderAttributesFromNode(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
) !void {
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_kind = NodeKind.fromNode(child);

        if (child_kind == .zx_attribute) {
            try w.writeAll(" ");

            // Get the actual attribute (first child)
            const attr_child = child.child(0) orelse continue;
            const attr_kind = NodeKind.fromNode(attr_child);

            switch (attr_kind) {
                .zx_builtin_attribute, .zx_regular_attribute => {
                    // Name
                    const name_node = attr_child.childByFieldName("name");
                    if (name_node) |n| {
                        const name_text = try self.getNodeText(n);
                        try w.writeAll(name_text);
                    }

                    // Value (optional)
                    const value_node = attr_child.childByFieldName("value");
                    if (value_node) |v| {
                        try w.writeAll("=");
                        // Write the value as-is from source
                        const v_start = v.startByte();
                        const v_end = v.endByte();
                        if (v_start < v_end and v_end <= self.source.len) {
                            try w.writeAll(self.source[v_start..v_end]);
                        }
                    }
                },
                else => {
                    // Fallback - render source
                    const c_start = child.startByte();
                    const c_end = child.endByte();
                    if (c_start < c_end and c_end <= self.source.len) {
                        try w.writeAll(self.source[c_start..c_end]);
                    }
                },
            }
        }
    }
}
