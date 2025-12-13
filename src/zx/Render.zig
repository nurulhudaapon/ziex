const std = @import("std");
const ts = @import("tree_sitter");
const Parse = @import("Parse.zig");

const Ast = Parse.Ast;
const NodeKind = Parse.NodeKind;

pub const FormatContext = struct {
    indent_level: u32 = 0,
    in_zx_block: bool = false,
    last_was_newline: bool = false,

    fn writeIndent(self: *FormatContext, w: *std.io.Writer) !void {
        const spaces = self.indent_level * 4;
        var i: u32 = 0;
        while (i < spaces) : (i += 1) {
            try w.writeAll(" ");
        }
        self.last_was_newline = false;
    }
};

pub fn renderNode(self: *Ast, node: ts.Node, w: *std.io.Writer) !void {
    var ctx = FormatContext{};
    try renderNodeWithContext(self, node, w, &ctx);
}

pub fn renderNodeWithContext(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
    ctx: *FormatContext,
) anyerror!void {
    const start_byte = node.startByte();
    const end_byte = node.endByte();
    const child_count = node.childCount();
    const node_type = node.kind();
    const node_kind = NodeKind.fromString(node_type);

    // Track if we're entering a zx_block
    const was_in_zx_block = ctx.in_zx_block;
    if (node_kind == .zx_block) {
        ctx.in_zx_block = true;
    }
    defer if (node_kind == .zx_block) {
        ctx.in_zx_block = was_in_zx_block;
    };

    // If not in zx_block, render Zig code as-is
    if (!ctx.in_zx_block) {
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
        return;
    }

    // We're in zx_block - apply formatting
    if (node_kind) |kind| {
        switch (kind) {
            .zx_block => {
                try renderBlock(self, node, w, ctx);
                return;
            },
            .zx_element => {
                try renderElement(self, node, w, ctx);
                return;
            },
            .zx_self_closing_element => {
                try renderSelfClosing(self, node, w, ctx);
                return;
            },
            .zx_start_tag => {
                try renderStartTag(self, node, w, ctx);
                return;
            },
            .zx_end_tag => {
                const tag_name = try getTagName(self, node);
                try w.writeAll("</");
                try w.writeAll(tag_name);
                try w.writeAll(">");
                return;
            },
            .zx_text => {
                try renderText(self, node, w, ctx);
                return;
            },
            .zx_child => {
                try renderChild(self, node, w, ctx);
                return;
            },
            .zx_expression_block => {
                try renderExprBlock(self, node, w, ctx);
                return;
            },
            else => {},
        }
    }

    // Default: render children
    if (child_count == 0) {
        if (start_byte < end_byte and end_byte <= self.source.len) {
            try w.writeAll(self.source[start_byte..end_byte]);
        }
        return;
    }

    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        try renderNodeWithContext(self, child, w, ctx);
    }
}

fn renderBlock(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
    ctx: *FormatContext,
) anyerror!void {
    const child_count = node.childCount();
    var i: u32 = 0;

    // Process children of zx_block
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        try renderNodeWithContext(self, child, w, ctx);
    }
}

fn renderChild(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
    ctx: *FormatContext,
) anyerror!void {
    const child_count = node.childCount();
    if (child_count == 0) return;

    // Check if this child only contains whitespace text - if so, skip it
    var i: u32 = 0;
    var has_meaningful_content = false;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_kind = NodeKind.fromString(child.kind());

        if (child_kind == .zx_text) {
            const text = try self.getNodeText(child);
            const trimmed = std.mem.trim(u8, text, &std.ascii.whitespace);
            if (trimmed.len > 0) {
                has_meaningful_content = true;
                break;
            }
        } else {
            has_meaningful_content = true;
            break;
        }
    }

    if (!has_meaningful_content) {
        return;
    }

    // Check if child should be on new line by looking at preceding whitespace
    const node_start = node.startByte();
    var should_newline = false;

    if (node_start > 0 and node_start <= self.source.len) {
        const check_start = if (node_start > 50) node_start - 50 else 0;
        const preceding = self.source[check_start..node_start];
        if (std.mem.indexOf(u8, preceding, "\n") != null) {
            should_newline = true;
            // Only add one newline, don't preserve extras from source
            if (!ctx.last_was_newline) {
                try w.writeAll("\n");
                ctx.last_was_newline = true;
            }
        }
    }

    if (should_newline) {
        try ctx.writeIndent(w);
        ctx.last_was_newline = false;
    }

    i = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        try renderNodeWithContext(self, child, w, ctx);
    }
}

fn renderElement(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
    ctx: *FormatContext,
) anyerror!void {
    const child_count = node.childCount();
    var i: u32 = 0;
    var previous_was_expression_block = false;

    // Render all children in order
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_kind = NodeKind.fromString(child.kind());

        if (child_kind == .zx_start_tag) {
            try renderNodeWithContext(self, child, w, ctx);
            ctx.indent_level += 1;
            previous_was_expression_block = false;
        } else if (child_kind == .zx_end_tag) {
            if (ctx.indent_level > 0) {
                ctx.indent_level -= 1;
            }
            // Check if end tag should be on new line
            // Always add newline if previous child was an expression block
            const child_start = child.startByte();
            var should_newline = previous_was_expression_block;

            if (!should_newline and child_start > 0 and child_start <= self.source.len) {
                const check_start = if (child_start > 50) child_start - 50 else 0;
                const preceding = self.source[check_start..child_start];
                if (std.mem.indexOf(u8, preceding, "\n") != null) {
                    should_newline = true;
                }
            }

            if (should_newline) {
                if (!ctx.last_was_newline) {
                    try w.writeAll("\n");
                    ctx.last_was_newline = true;
                }
                try ctx.writeIndent(w);
            }
            try renderNodeWithContext(self, child, w, ctx);
            previous_was_expression_block = false;
        } else {
            // Check if this is an expression block
            if (child_kind == .zx_expression_block) {
                previous_was_expression_block = true;
            } else {
                previous_was_expression_block = false;
            }
            try renderNodeWithContext(self, child, w, ctx);
        }
    }
}

fn renderStartTag(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
    ctx: *FormatContext,
) anyerror!void {
    // Tag Start: <
    try w.writeAll("<");

    // Tag Name - <|div|
    const tag_name_node = node.childByFieldName("name");
    if (tag_name_node) |name_node| {
        const tag_name_text = try self.getNodeText(name_node);
        try w.writeAll(tag_name_text);
    } else {
        return error.InvalidNode;
    }

    // Render all attributes
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_kind = NodeKind.fromString(child.kind());

        if (child_kind == .zx_attribute) {
            try renderAttr(self, child, w, ctx);
        }
    }

    // Tag End: >
    try w.writeAll(">");
}

fn renderSelfClosing(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
    ctx: *FormatContext,
) anyerror!void {
    // Tag Start: <
    try w.writeAll("<");

    // Tag Name
    const tag_name_node = node.childByFieldName("name");
    if (tag_name_node) |name_node| {
        const tag_name_text = try self.getNodeText(name_node);
        try w.writeAll(tag_name_text);
    } else {
        return error.InvalidNode;
    }

    // Render all attributes
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_kind = NodeKind.fromString(child.kind());

        if (child_kind == .zx_attribute) {
            try renderAttr(self, child, w, ctx);
        }
    }

    // Tag End: />
    try w.writeAll(" />");
}

fn renderAttr(self: *Ast, node: ts.Node, w: *std.io.Writer, ctx: *FormatContext) !void {
    // zx_attribute wraps either zx_builtin_attribute or zx_regular_attribute
    // Get the actual attribute node (first child)
    const child_count = node.childCount();
    if (child_count == 0) return;

    const attr_node = node.child(0) orelse return;
    const attr_kind = NodeKind.fromString(attr_node.kind());

    if (attr_kind) |kind| {
        switch (kind) {
            .zx_builtin_attribute => {
                try renderBuiltinAttr(self, attr_node, w, ctx);
            },
            .zx_regular_attribute => {
                try renderRegularAttr(self, attr_node, w, ctx);
            },
            else => {
                // Fallback: render as-is
                const start_byte = node.startByte();
                const end_byte = node.endByte();
                if (start_byte < end_byte and end_byte <= self.source.len) {
                    try w.writeAll(self.source[start_byte..end_byte]);
                }
            },
        }
    }
}

fn renderBuiltinAttr(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
    ctx: *FormatContext,
) !void {
    // Builtin attributes: @name={value}
    // Write space before attribute
    try w.writeAll(" ");

    // Get the name field
    const name_node = node.childByFieldName("name");
    if (name_node) |n| {
        const name_text = try self.getNodeText(n);
        try w.writeAll(name_text);
    } else {
        return error.InvalidNode;
    }

    // Get the value field
    const value_node = node.childByFieldName("value");
    if (value_node) |v| {
        try w.writeAll("=");
        try renderAttrValue(self, v, w, ctx);
    }
}

fn renderRegularAttr(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
    ctx: *FormatContext,
) !void {
    // Regular attributes: name="value" or name (boolean attribute)
    // Write space before attribute
    try w.writeAll(" ");

    // Get the name field
    const name_node = node.childByFieldName("name");
    if (name_node) |n| {
        const name_text = try self.getNodeText(n);
        try w.writeAll(name_text);
    } else {
        return error.InvalidNode;
    }

    // Get the value field (optional for boolean attributes)
    const value_node = node.childByFieldName("value");
    if (value_node) |v| {
        try w.writeAll("=");
        try renderAttrValue(self, v, w, ctx);
    }
}

fn renderAttrValue(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
    ctx: *FormatContext,
) !void {
    // zx_attribute_value is a choice: it IS either zx_expression_block or zx_string_literal
    const node_kind = NodeKind.fromString(node.kind());

    if (node_kind) |kind| {
        switch (kind) {
            .zx_expression_block => {
                // Render expression block: {expression}
                try renderExprBlock(self, node, w, ctx);
            },
            .zx_string_literal => {
                // Render string literal as-is
                const start_byte = node.startByte();
                const end_byte = node.endByte();
                if (start_byte < end_byte and end_byte <= self.source.len) {
                    try w.writeAll(self.source[start_byte..end_byte]);
                }
            },
            .zx_attribute_value => {
                // If it's still zx_attribute_value, check children (fallback for edge cases)
                const child_count = node.childCount();
                if (child_count > 0) {
                    var i: u32 = 0;
                    while (i < child_count) : (i += 1) {
                        const child = node.child(i) orelse continue;
                        try renderAttrValue(self, child, w, ctx);
                    }
                } else {
                    // Fallback: render as-is
                    const start_byte = node.startByte();
                    const end_byte = node.endByte();
                    if (start_byte < end_byte and end_byte <= self.source.len) {
                        try w.writeAll(self.source[start_byte..end_byte]);
                    }
                }
            },
            else => {
                // Fallback: render as-is
                const start_byte = node.startByte();
                const end_byte = node.endByte();
                if (start_byte < end_byte and end_byte <= self.source.len) {
                    try w.writeAll(self.source[start_byte..end_byte]);
                }
            },
        }
    } else {
        // Unknown node type, render as-is
        const start_byte = node.startByte();
        const end_byte = node.endByte();
        if (start_byte < end_byte and end_byte <= self.source.len) {
            try w.writeAll(self.source[start_byte..end_byte]);
        }
    }
}

fn renderText(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
    ctx: *FormatContext,
) anyerror!void {
    _ = ctx;
    const start_byte = node.startByte();
    const end_byte = node.endByte();

    if (start_byte >= end_byte or end_byte > self.source.len) return;

    // Get the text content
    const text = self.source[start_byte..end_byte];
    const trimmed = std.mem.trim(u8, text, &std.ascii.whitespace);
    if (trimmed.len > 0) {
        try w.writeAll(trimmed);
    }
}

fn renderExprBlock(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
    ctx: *FormatContext,
) anyerror!void {
    // Write opening brace
    try w.writeAll("{");

    const child_count = node.childCount();
    var i: u32 = 0;
    var found_control_flow = false;
    var is_for_expression = false;
    var is_if_expression = false;

    // Check for control flow expressions
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_type = child.kind();
        const child_kind = NodeKind.fromString(child_type);

        // Check for control flow expressions
        if (child_kind) |kind| {
            switch (kind) {
                .if_expression => {
                    try renderIf(self, child, w, ctx);
                    found_control_flow = true;
                    is_if_expression = true;
                    break;
                },
                .for_expression => {
                    try renderFor(self, child, w, ctx);
                    found_control_flow = true;
                    is_for_expression = true;
                    break;
                },
                .switch_expression => {
                    try renderSwitch(self, child, w, ctx);
                    found_control_flow = true;
                    break;
                },
                else => {},
            }
        }
    }

    // If no control flow expression found, render as simple expression
    if (!found_control_flow) {
        // Render the expression content (skip braces)
        i = 0;
        while (i < child_count) : (i += 1) {
            const child = node.child(i) orelse continue;
            const child_type = child.kind();

            // Check if it's a zx_block
            const child_kind = NodeKind.fromString(child_type);
            if (child_kind == .zx_block) {
                try renderBlock(self, child, w, ctx);
            } else {
                // Regular expression - normalize whitespace
                const expr_text = try self.getNodeText(child);
                const normalized = try normalizeExpression(self.allocator, expr_text);
                defer self.allocator.free(normalized);
                try w.writeAll(normalized);
            }
        }
    }

    // Write closing brace
    // Check if we need to add newline and indentation before closing brace
    // This happens when the expression block contains a zx_block that was formatted with newlines
    if (found_control_flow) {
        // For for and if expressions, the closing paren should be on the same line as the closing brace
        // So we don't add a newline before the closing brace for these expressions
        if (!is_for_expression and !is_if_expression) {
            // For other control flow expressions, check if we need to add newline before closing brace
            // If the expression block spans multiple lines, add proper formatting
            const node_start = node.startByte();
            const node_end = node.endByte();
            if (node_start < node_end and node_end <= self.source.len) {
                const block_text = self.source[node_start..node_end];
                if (std.mem.indexOf(u8, block_text, "\n") != null) {
                    // Expression block spans multiple lines, add newline before closing brace if needed
                    if (!ctx.last_was_newline) {
                        try w.writeAll("\n");
                        try ctx.writeIndent(w);
                    }
                    ctx.last_was_newline = false;
                }
            }
        }
    }
    try w.writeAll("}");
    // After closing brace, we're not on a newline anymore
    ctx.last_was_newline = false;
}

fn renderIf(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
    ctx: *FormatContext,
) anyerror!void {
    // if_expression has: condition field, then zx_block nodes
    var condition_node: ?ts.Node = null;
    var then_node: ?ts.Node = null;
    var else_node: ?ts.Node = null;

    const child_count = node.childCount();
    var i: u32 = 0;
    var zx_block_count: u32 = 0;

    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_type = child.kind();

        // Check if this is the condition field
        const field_name = node.fieldNameForChild(i);
        if (field_name) |name| {
            if (std.mem.eql(u8, name, "condition")) {
                condition_node = child;
                continue;
            }
        }

        // Check for zx_block nodes (then and else branches)
        const child_kind = NodeKind.fromString(child_type);
        if (child_kind == .zx_block) {
            if (zx_block_count == 0) {
                then_node = child;
            } else if (zx_block_count == 1) {
                else_node = child;
            }
            zx_block_count += 1;
        }
    }

    if (condition_node != null and then_node != null) {
        // Save the indent level at the start (this matches the opening { of the expression block)
        const base_indent = ctx.indent_level;

        try w.writeAll("if ");

        // Write condition - get text and wrap in parentheses if needed
        const condition_text = try self.getNodeText(condition_node.?);
        const cond_trimmed = std.mem.trim(u8, condition_text, &std.ascii.whitespace);
        if (cond_trimmed.len > 0 and cond_trimmed[0] == '(' and cond_trimmed[cond_trimmed.len - 1] == ')') {
            try w.writeAll(cond_trimmed);
        } else {
            try w.writeAll("(");
            try w.writeAll(cond_trimmed);
            try w.writeAll(")");
        }
        try w.writeAll(" ");

        // Handle then branch
        const then_kind = NodeKind.fromString(then_node.?.kind());
        var then_was_multiline = false;
        if (then_kind == .zx_block) {
            // Extract inner element and write parentheses ourselves
            const then_block = then_node.?;
            var then_inner_element: ?ts.Node = null;
            const then_block_child_count = then_block.childCount();
            var j: u32 = 0;
            while (j < then_block_child_count) : (j += 1) {
                const then_block_child = then_block.child(j) orelse continue;
                const then_block_child_type = then_block_child.kind();
                const then_block_child_kind = NodeKind.fromString(then_block_child_type);
                if (then_block_child_kind) |kind| {
                    switch (kind) {
                        .zx_element, .zx_self_closing_element, .zx_fragment => {
                            then_inner_element = then_block_child;
                            break;
                        },
                        else => {},
                    }
                }
            }

            if (then_inner_element) |element| {
                // Write opening paren (space already written before)
                try w.writeAll("(");

                // Check if element is multiline
                const element_start = element.startByte();
                const element_end = element.endByte();
                var is_multiline = false;
                if (element_start < element_end and element_end <= self.source.len) {
                    const element_text = self.source[element_start..element_end];
                    if (std.mem.indexOf(u8, element_text, "\n") != null) {
                        is_multiline = true;
                        then_was_multiline = true;
                    }
                }

                if (is_multiline) {
                    // Multiline - add newline and indent
                    try w.writeAll("\n");
                    ctx.indent_level += 1;
                    try ctx.writeIndent(w);
                    ctx.last_was_newline = false;
                } else {
                    // Single line - just render inline
                    ctx.last_was_newline = false;
                }

                // Render the element itself
                try renderNodeWithContext(self, element, w, ctx);

                // Write closing paren - should be on a newline
                // For multiline, the closing paren should be on its own line
                // Then "else" will come after it on the same line
                if (is_multiline) {
                    // Add newline and restore to base indent level
                    if (!ctx.last_was_newline) {
                        try w.writeAll("\n");
                    }
                    ctx.indent_level = base_indent;
                    try ctx.writeIndent(w);
                } else {
                    // Single line - restore to base indent level
                    ctx.indent_level = base_indent;
                }
                try w.writeAll(")");
                // After closing paren, we're ready for "else" on the same line (if multiline)
                ctx.last_was_newline = false;
            }
        } else {
            const then_text = try self.getNodeText(then_node.?);
            const normalized = try normalizeExpression(self.allocator, then_text);
            defer self.allocator.free(normalized);
            try w.writeAll(normalized);
        }

        if (else_node) |else_n| {
            // If then branch was multiline, "else" should be on the same line as the closing paren
            // Otherwise, "else" comes after a space
            if (then_was_multiline) {
                // "else" comes on the same line as the closing paren of then branch
                try w.writeAll(" else");
            } else {
                try w.writeAll(" else");
            }

            const else_kind = NodeKind.fromString(else_n.kind());
            if (else_kind == .zx_block) {
                // Extract inner element and write parentheses ourselves
                const else_block = else_n;
                var else_inner_element: ?ts.Node = null;
                const else_block_child_count = else_block.childCount();
                var j: u32 = 0;
                while (j < else_block_child_count) : (j += 1) {
                    const else_block_child = else_block.child(j) orelse continue;
                    const else_block_child_type = else_block_child.kind();
                    const else_block_child_kind = NodeKind.fromString(else_block_child_type);
                    if (else_block_child_kind) |kind| {
                        switch (kind) {
                            .zx_element, .zx_self_closing_element, .zx_fragment => {
                                else_inner_element = else_block_child;
                                break;
                            },
                            else => {},
                        }
                    }
                }

                if (else_inner_element) |element| {
                    // Write opening paren with space before it
                    try w.writeAll(" (");

                    // Check if element is multiline
                    const element_start = element.startByte();
                    const element_end = element.endByte();
                    var is_multiline = false;
                    if (element_start < element_end and element_end <= self.source.len) {
                        const element_text = self.source[element_start..element_end];
                        if (std.mem.indexOf(u8, element_text, "\n") != null) {
                            is_multiline = true;
                        }
                    }

                    if (is_multiline) {
                        // Multiline - add newline and indent
                        try w.writeAll("\n");
                        ctx.indent_level += 1;
                        try ctx.writeIndent(w);
                        ctx.last_was_newline = false;
                    } else {
                        // Single line - just a space
                        ctx.last_was_newline = false;
                    }

                    // Render the element itself
                    try renderNodeWithContext(self, element, w, ctx);

                    // Write closing paren - should be on a newline with the closing brace
                    if (is_multiline) {
                        // Add newline and restore to base indent level
                        if (!ctx.last_was_newline) {
                            try w.writeAll("\n");
                        }
                        ctx.indent_level = base_indent;
                        try ctx.writeIndent(w);
                    } else {
                        // Single line - restore to base indent level
                        ctx.indent_level = base_indent;
                    }
                    try w.writeAll(")");
                    ctx.last_was_newline = false;
                }
            } else {
                try w.writeAll(" ");
                const else_text = try self.getNodeText(else_n);
                const normalized = try normalizeExpression(self.allocator, else_text);
                defer self.allocator.free(normalized);
                try w.writeAll(normalized);
            }
        }
    }
}

fn renderFor(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
    ctx: *FormatContext,
) anyerror!void {
    // for_expression has: identifier (iterable), payload, zx_block (body)
    var iterable_node: ?ts.Node = null;
    var payload_node: ?ts.Node = null;
    var body_node: ?ts.Node = null;

    const child_count = node.childCount();
    var i: u32 = 0;

    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_type = child.kind();
        const child_kind = NodeKind.fromString(child_type);

        if (child_kind) |kind| {
            switch (kind) {
                .identifier => {
                    if (iterable_node == null) {
                        iterable_node = child;
                    }
                },
                .payload => {
                    payload_node = child;
                },
                .zx_block => {
                    body_node = child;
                },
                else => {},
            }
        }
    }

    if (iterable_node != null and payload_node != null and body_node != null) {
        // Save the indent level at the start (this matches the opening { of the expression block)
        const base_indent = ctx.indent_level;

        const iterable_text = try self.getNodeText(iterable_node.?);
        const payload_text = try self.getNodeText(payload_node.?);

        try w.writeAll("for (");
        try w.writeAll(iterable_text);
        try w.writeAll(") ");
        try w.writeAll(payload_text);

        // Render body (should be zx_block)
        // Instead of calling renderBlock, we extract the inner element and write parens ourselves
        if (body_node) |body| {
            // Find the zx_element, zx_self_closing_element, or zx_fragment inside the zx_block
            var inner_element: ?ts.Node = null;
            const body_child_count = body.childCount();
            var j: u32 = 0;
            while (j < body_child_count) : (j += 1) {
                const body_child = body.child(j) orelse continue;
                const body_child_type = body_child.kind();
                const body_child_kind = NodeKind.fromString(body_child_type);
                if (body_child_kind) |kind| {
                    switch (kind) {
                        .zx_element, .zx_self_closing_element, .zx_fragment => {
                            inner_element = body_child;
                            break;
                        },
                        else => {},
                    }
                }
            }

            if (inner_element) |element| {
                // Write opening paren with space before it - no newline after it
                try w.writeAll(" (");

                // Check if element is multiline to decide if we need indentation
                const element_start = element.startByte();
                const element_end = element.endByte();
                var is_multiline = false;
                if (element_start < element_end and element_end <= self.source.len) {
                    const element_text = self.source[element_start..element_end];
                    if (std.mem.indexOf(u8, element_text, "\n") != null) {
                        is_multiline = true;
                    }
                }

                if (is_multiline) {
                    // Multiline - add newline and indent
                    try w.writeAll("\n");
                    ctx.indent_level += 1;
                    try ctx.writeIndent(w);
                    ctx.last_was_newline = false;
                } else {
                    // Single line - just a space
                    ctx.last_was_newline = false;
                }

                // Render the element itself (without the zx_block wrapper)
                try renderNodeWithContext(self, element, w, ctx);

                // Write closing paren - should be on a newline with the closing brace
                if (is_multiline) {
                    // Add newline and restore to base indent level
                    if (!ctx.last_was_newline) {
                        try w.writeAll("\n");
                    }
                    // Restore to the indent level of the opening { of the expression block
                    ctx.indent_level = base_indent;
                    try ctx.writeIndent(w);
                } else {
                    // Single line - restore to base indent level
                    ctx.indent_level = base_indent;
                }
                try w.writeAll(")");
                // Make sure we're not on a newline so the closing brace comes right after
                ctx.last_was_newline = false;
            }
        }
    }
}

fn renderSwitch(
    self: *Ast,
    node: ts.Node,
    w: *std.io.Writer,
    ctx: *FormatContext,
) anyerror!void {
    // switch_expression: 'switch' '(' expr ')' '{' switch_case... '}'
    var switch_expr: ?[]const u8 = null;
    var cases = std.ArrayList(struct { pattern: []const u8, value: ts.Node }){};
    defer cases.deinit(self.allocator);

    const child_count = node.childCount();
    var i: u32 = 0;

    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_type = child.kind();
        const child_kind = NodeKind.fromString(child_type);

        // Find the switch expression (first non-switch_case child)
        if (child_kind) |kind| {
            switch (kind) {
                .switch_case => {
                    // Parse switch case: pattern '=>' value
                    var pattern_node: ?ts.Node = null;
                    var value_node: ?ts.Node = null;
                    var seen_arrow = false;

                    const case_child_count = child.childCount();
                    var j: u32 = 0;
                    while (j < case_child_count) : (j += 1) {
                        const case_child = child.child(j) orelse continue;
                        const case_child_type = case_child.kind();

                        if (std.mem.eql(u8, case_child_type, "=>")) {
                            seen_arrow = true;
                        } else if (!seen_arrow and pattern_node == null) {
                            pattern_node = case_child;
                        } else if (seen_arrow and value_node == null) {
                            value_node = case_child;
                        }
                    }

                    if (pattern_node) |p| {
                        const pattern_text = try self.getNodeText(p);
                        try cases.append(self.allocator, .{
                            .pattern = pattern_text,
                            .value = value_node orelse continue,
                        });
                    }
                },
                else => {
                    if (switch_expr == null) {
                        switch_expr = try self.getNodeText(child);
                    }
                },
            }
        } else {
            if (switch_expr == null) {
                switch_expr = try self.getNodeText(child);
            }
        }
    }

    if (switch_expr != null) {
        try w.writeAll("switch (");
        try w.writeAll(switch_expr.?);
        try w.writeAll(") {");

        // Render cases
        const saved_indent = ctx.indent_level;
        for (cases.items, 0..) |case, idx| {
            if (idx > 0) {
                try w.writeAll(",");
            }
            try w.writeAll("\n");
            ctx.indent_level = saved_indent + 1;
            try ctx.writeIndent(w);
            try w.writeAll(case.pattern);
            try w.writeAll(" => ");

            const value_kind = NodeKind.fromString(case.value.kind());
            if (value_kind == .zx_block) {
                // Force newline and indentation for zx_block in expression
                try w.writeAll("\n");
                const block_indent = ctx.indent_level;
                ctx.indent_level += 1;
                try ctx.writeIndent(w);
                ctx.last_was_newline = false;
                try renderBlock(self, case.value, w, ctx);
                // Restore indent level - the zx_block's closing paren should be at the same level as opening
                ctx.indent_level = block_indent;
            } else {
                const value_text = try self.getNodeText(case.value);
                const normalized = try normalizeExpression(self.allocator, value_text);
                defer self.allocator.free(normalized);
                try w.writeAll(normalized);
            }
        }

        try w.writeAll("\n");
        ctx.indent_level = saved_indent;
        try ctx.writeIndent(w);
        try w.writeAll("}");
    }
}

fn normalizeExpression(allocator: std.mem.Allocator, expr: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    defer result.deinit();

    var i: usize = 0;
    var last_was_space = false;

    while (i < expr.len) : (i += 1) {
        const c = expr[i];
        if (std.ascii.isWhitespace(c)) {
            if (!last_was_space and result.items.len > 0) {
                try result.append(' ');
                last_was_space = true;
            }
        } else {
            try result.append(c);
            last_was_space = false;
        }
    }

    return result.toOwnedSlice();
}

fn getTagName(self: *Ast, end_tag_node: ts.Node) ![]const u8 {
    const child_count = end_tag_node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = end_tag_node.child(i) orelse continue;
        const child_kind = NodeKind.fromString(child.kind());
        if (child_kind == .zx_tag_name) {
            return try self.getNodeText(child);
        }
    }
    return "";
}
