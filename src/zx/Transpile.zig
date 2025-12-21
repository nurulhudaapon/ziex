const std = @import("std");
const ts = @import("tree_sitter");
const sourcemap = @import("sourcemap.zig");
const Parse = @import("Parse.zig");

const Ast = Parse.Ast;
const NodeKind = Parse.NodeKind;

/// Token types that should be skipped during expression block processing
const SkipTokens = enum {
    open_brace,
    close_brace,
    open_paren,
    close_paren,
    other,

    fn from(token: []const u8) SkipTokens {
        if (std.mem.eql(u8, token, "{")) return .open_brace;
        if (std.mem.eql(u8, token, "}")) return .close_brace;
        if (std.mem.eql(u8, token, "(")) return .open_paren;
        if (std.mem.eql(u8, token, ")")) return .close_paren;
        return .other;
    }
};

pub const TranspileContext = struct {
    output: std.array_list.Managed(u8),
    source: []const u8,
    sourcemap_builder: sourcemap.Builder,
    current_line: i32 = 0,
    current_column: i32 = 0,
    track_mappings: bool,
    indent_level: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, source: []const u8, track_mappings: bool) TranspileContext {
        return .{
            .output = std.array_list.Managed(u8).init(allocator),
            .source = source,
            .sourcemap_builder = sourcemap.Builder.init(allocator),
            .track_mappings = track_mappings,
        };
    }

    pub fn deinit(self: *TranspileContext) void {
        self.output.deinit();
        self.sourcemap_builder.deinit();
    }

    fn write(self: *TranspileContext, bytes: []const u8) !void {
        try self.output.appendSlice(bytes);
        self.updatePosition(bytes);
    }

    fn writeWithMapping(self: *TranspileContext, bytes: []const u8, source_line: i32, source_column: i32) !void {
        if (self.track_mappings and bytes.len > 0) {
            try self.sourcemap_builder.addMapping(.{
                .generated_line = self.current_line,
                .generated_column = self.current_column,
                .source_line = source_line,
                .source_column = source_column,
            });
        }
        try self.write(bytes);
    }

    fn writeWithMappingFromByte(self: *TranspileContext, bytes: []const u8, source_byte: u32, ast: *const Ast) !void {
        const pos = ast.getLineColumn(source_byte);
        try self.writeWithMapping(bytes, pos.line, pos.column);
    }

    fn updatePosition(self: *TranspileContext, bytes: []const u8) void {
        for (bytes) |byte| {
            if (byte == '\n') {
                self.current_line += 1;
                self.current_column = 0;
            } else {
                self.current_column += 1;
            }
        }
    }

    fn writeIndent(self: *TranspileContext) !void {
        const spaces = self.indent_level * 4;
        var i: u32 = 0;
        while (i < spaces) : (i += 1) {
            try self.write(" ");
        }
    }

    pub fn finalizeSourceMap(self: *TranspileContext) !sourcemap.SourceMap {
        return try self.sourcemap_builder.build();
    }
};

pub fn transpileNode(self: *Ast, node: ts.Node, ctx: *TranspileContext) error{OutOfMemory}!void {
    const start_byte = node.startByte();
    const end_byte = node.endByte();
    const node_kind = NodeKind.fromNode(node);

    // Check if this is a ZX block or return expression that needs special handling
    switch (node_kind) {
        .zx_block => {
            // For inline zx_blocks (not in return statements), just transpile the content
            try transpileBlock(self, node, ctx);
            return;
        },
        .variable_declaration => {
            // Check if this variable declaration contains @jsImport
            if (try containsJsImport(self, node)) {
                // Comment out the entire declaration
                try ctx.writeWithMappingFromByte("// ", start_byte, self);
                if (start_byte < end_byte and end_byte <= self.source.len) {
                    try ctx.write(self.source[start_byte..end_byte]);
                }
                return;
            }
        },
        .return_expression => {
            const child_count = node.childCount();
            var has_zx_block = false;
            var i: u32 = 0;

            while (i < child_count) : (i += 1) {
                const child = node.child(i) orelse continue;
                const child_kind = NodeKind.fromNode(child);
                if (child_kind == .zx_block) {
                    has_zx_block = true;
                    break;
                }
            }

            if (has_zx_block) {
                // Special handling for return (ZX)
                try transpileReturn(self, node, ctx);
                return;
            }
        },
        .builtin_function => {
            const had_output = try transpileBuiltin(self, node, ctx);
            if (had_output)
                return;
        },
        else => {},
    }

    // For regular Zig code, copy as-is with source mapping
    const child_count = node.childCount();
    if (child_count == 0) {
        if (start_byte < end_byte and end_byte <= self.source.len) {
            const text = self.source[start_byte..end_byte];
            try ctx.writeWithMappingFromByte(text, start_byte, self);
        }
        return;
    }

    // Recursively process children
    var current_pos = start_byte;
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_start = child.startByte();
        const child_end = child.endByte();

        if (current_pos < child_start and child_start <= self.source.len) {
            const text = self.source[current_pos..child_start];
            try ctx.writeWithMappingFromByte(text, current_pos, self);
        }

        try transpileNode(self, child, ctx);
        current_pos = child_end;
    }

    if (current_pos < end_byte and end_byte <= self.source.len) {
        const text = self.source[current_pos..end_byte];
        try ctx.writeWithMappingFromByte(text, current_pos, self);
    }
}

/// Check if a node contains @jsImport builtin
fn containsJsImport(self: *Ast, node: ts.Node) !bool {
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_kind = NodeKind.fromNode(child);

        if (child_kind == .builtin_function) {
            // Check if this builtin is @jsImport
            const builtin_child_count = child.childCount();
            var j: u32 = 0;
            while (j < builtin_child_count) : (j += 1) {
                const builtin_child = child.child(j) orelse continue;
                if (NodeKind.fromNode(builtin_child) == .builtin_identifier) {
                    const ident = try self.getNodeText(builtin_child);
                    if (std.mem.eql(u8, ident, "@jsImport")) {
                        return true;
                    }
                }
            }
        }

        // Recursively check children
        if (try containsJsImport(self, child)) {
            return true;
        }
    }
    return false;
}

// @import("component.zx") --> @import("component.zig")
pub fn transpileBuiltin(self: *Ast, node: ts.Node, ctx: *TranspileContext) !bool {
    var had_output = false;
    var builtin_identifier: ?[]const u8 = null;
    var import_string: ?[]const u8 = null;

    const child_count = node.childCount();
    var i: u32 = 0;

    // First pass: collect builtin identifier and import string
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_kind = NodeKind.fromNode(child);

        switch (child_kind) {
            .builtin_identifier => {
                builtin_identifier = try self.getNodeText(child);
            },
            .arguments => {
                // Look for string inside arguments
                const args_child_count = child.childCount();
                var j: u32 = 0;
                while (j < args_child_count) : (j += 1) {
                    const arg_child = child.child(j) orelse continue;
                    const arg_child_kind = NodeKind.fromNode(arg_child);

                    if (arg_child_kind == .string) {
                        // Get the string with quotes
                        const full_string = try self.getNodeText(arg_child);

                        // Look for string_content inside
                        const string_child_count = arg_child.childCount();
                        var k: u32 = 0;
                        while (k < string_child_count) : (k += 1) {
                            const str_child = arg_child.child(k) orelse continue;
                            const str_child_kind = NodeKind.fromNode(str_child);

                            if (str_child_kind == .string_content) {
                                import_string = try self.getNodeText(str_child);
                                break;
                            }
                        }

                        // If no string_content found, use full_string but strip quotes
                        if (import_string == null and full_string.len >= 2) {
                            import_string = full_string[1 .. full_string.len - 1];
                        }
                        break;
                    }
                }
            },
            else => {},
        }
    }

    // Check if this is @import with a .zx file
    if (builtin_identifier) |ident| {
        if (std.mem.eql(u8, ident, "@import")) {
            if (import_string) |import_path| {
                // Check if it ends with .zx
                if (std.mem.endsWith(u8, import_path, ".zx")) {
                    // Write @import with transformed path
                    try ctx.writeWithMappingFromByte("@import", node.startByte(), self);
                    try ctx.write("(\"");

                    // Write path with .zig instead of .zx
                    const base_path = import_path[0 .. import_path.len - 3]; // Remove ".zx"
                    try ctx.write(base_path);
                    try ctx.write(".zig\")");

                    had_output = true;
                }
            }
        }
    }

    return had_output;
}

pub fn transpileReturn(self: *Ast, node: ts.Node, ctx: *TranspileContext) !void {
    // Handle: return (<zx>...</zx>)
    // This should NOT initialize _zx here - that's done in the parent block
    const child_count = node.childCount();
    var zx_block_node: ?ts.Node = null;

    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_kind = NodeKind.fromNode(child);

        if (child_kind == .zx_block) {
            zx_block_node = child;
            break;
        }
    }

    if (zx_block_node) |zx_node| {
        // Find the element inside the zx_block
        const zx_child_count = zx_node.childCount();
        var j: u32 = 0;
        while (j < zx_child_count) : (j += 1) {
            const child = zx_node.child(j) orelse continue;
            const child_kind = NodeKind.fromNode(child);

            switch (child_kind) {
                .zx_element, .zx_self_closing_element, .zx_fragment => {
                    // Check if we need to initialize _zx with allocator
                    const allocator_value = try getAllocatorAttribute(self, child);

                    try ctx.writeWithMappingFromByte("var", node.startByte(), self);
                    try ctx.write(" _zx = zx.");
                    if (allocator_value) |alloc| {
                        try ctx.write("initWithAllocator(");
                        try ctx.write(alloc);
                        try ctx.write(")");
                    } else {
                        try ctx.write("init()");
                    }
                    try ctx.write(";\n");
                    try ctx.writeIndent();
                    try ctx.writeWithMappingFromByte("return", node.startByte(), self);
                    try ctx.write(" ");
                    try transpileElement(self, child, ctx, true);
                    return;
                },
                else => {},
            }
        }
    }
}

pub fn transpileBlock(self: *Ast, node: ts.Node, ctx: *TranspileContext) !void {
    // This is for zx_block nodes found inside expressions (not top-level)
    // Extract the element and transpile it without initialization
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_kind = NodeKind.fromNode(child);

        switch (child_kind) {
            .zx_element, .zx_self_closing_element, .zx_fragment => {
                try transpileElement(self, child, ctx, false);
                return;
            },
            else => {},
        }
    }
}

/// Returns the allocator attribute value text if found, null otherwise
pub fn getAllocatorAttribute(self: *Ast, node: ts.Node) !?[]const u8 {
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        if (NodeKind.fromNode(child) != .zx_start_tag) continue;

        // Check attributes in start tag
        const tag_children = child.childCount();
        var j: u32 = 0;
        while (j < tag_children) : (j += 1) {
            const attr = child.child(j) orelse continue;
            const attr_kind = NodeKind.fromNode(attr);

            if (attr_kind != .zx_attribute and attr_kind != .zx_builtin_attribute) continue;

            // Get the actual attribute node (zx_attribute wraps zx_builtin_attribute)
            const actual_attr = if (attr_kind == .zx_attribute) attr.child(0) orelse continue else attr;

            // Use field name to get name and value directly
            const name_node = actual_attr.childByFieldName("name") orelse continue;
            const name = try self.getNodeText(name_node);
            if (std.mem.eql(u8, name, "@allocator")) {
                const value_node = actual_attr.childByFieldName("value") orelse return "allocator";
                return try getAttributeValue(self, value_node);
            }
        }
    }
    return null;
}

pub fn transpileElement(self: *Ast, node: ts.Node, ctx: *TranspileContext, is_root: bool) !void {
    const node_kind = NodeKind.fromNode(node);
    switch (node_kind) {
        .zx_fragment => try transpileFragment(self, node, ctx, is_root),
        .zx_self_closing_element => try transpileSelfClosing(self, node, ctx, is_root),
        .zx_element => try transpileFullElement(self, node, ctx, is_root),
        else => unreachable,
    }
}

pub fn transpileFragment(self: *Ast, node: ts.Node, ctx: *TranspileContext, is_root: bool) !void {
    _ = is_root;
    _ = node;
    _ = self;
    _ = ctx;
    // TODO: Implement fragment transpilation
    // Fragments become anonymous containers
}

pub fn isCustomComponent(tag: []const u8) bool {
    return tag.len > 0 and std.ascii.isUpper(tag[0]);
}

pub fn transpileSelfClosing(self: *Ast, node: ts.Node, ctx: *TranspileContext, is_root: bool) !void {
    _ = is_root;

    var tag_name: ?[]const u8 = null;
    var attributes = std.ArrayList(ZxAttribute){};
    defer attributes.deinit(ctx.output.allocator);

    // Parse the self-closing element
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;

        switch (NodeKind.fromNode(child)) {
            .zx_tag_name => tag_name = try self.getNodeText(child),
            .zx_attribute, .zx_builtin_attribute, .zx_regular_attribute => {
                const attr = try parseAttribute(self, child);
                if (attr.name.len > 0) {
                    try attributes.append(ctx.output.allocator, attr);
                }
            },
            else => {},
        }
    }

    const tag = tag_name orelse return;

    if (isCustomComponent(tag)) {
        try writeCustomComponent(self, node, tag, attributes.items, ctx);
    } else {
        try writeHtmlElement(self, node, tag, attributes.items, &.{}, ctx);
    }
}

pub fn transpileFullElement(self: *Ast, node: ts.Node, ctx: *TranspileContext, is_root: bool) !void {
    _ = is_root;

    // Parse element structure
    var tag_name: ?[]const u8 = null;
    var attributes = std.ArrayList(ZxAttribute){};
    defer attributes.deinit(ctx.output.allocator);
    var children = std.ArrayList(ts.Node){};
    defer children.deinit(ctx.output.allocator);

    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;

        switch (NodeKind.fromNode(child)) {
            .zx_start_tag => {
                // Parse tag name and attributes from start tag
                const tag_children = child.childCount();
                var j: u32 = 0;
                while (j < tag_children) : (j += 1) {
                    const tag_child = child.child(j) orelse continue;

                    switch (NodeKind.fromNode(tag_child)) {
                        .zx_tag_name => tag_name = try self.getNodeText(tag_child),
                        .zx_attribute, .zx_builtin_attribute, .zx_regular_attribute => {
                            const attr = try parseAttribute(self, tag_child);
                            if (attr.name.len > 0) {
                                try attributes.append(ctx.output.allocator, attr);
                            }
                        },
                        else => {},
                    }
                }
            },
            .zx_child => try children.append(ctx.output.allocator, child),
            else => {},
        }
    }

    const tag = tag_name orelse return;

    // Custom component with children
    if (isCustomComponent(tag)) {
        try writeCustomComponent(self, node, tag, attributes.items, ctx);
        return;
    }

    // Regular HTML element
    try writeHtmlElement(self, node, tag, attributes.items, children.items, ctx);
}

/// Write a custom component: _zx.lazy(Component, .{ .prop = value })
fn writeCustomComponent(self: *Ast, node: ts.Node, tag: []const u8, attributes: []const ZxAttribute, ctx: *TranspileContext) !void {
    try ctx.writeWithMappingFromByte("_zx.lazy", node.startByte(), self);
    try ctx.write("(");
    try ctx.write(tag);
    try ctx.write(", .{");

    var first_prop = true;
    for (attributes) |attr| {
        if (attr.is_builtin) continue;
        if (!first_prop) try ctx.write(",");
        first_prop = false;

        try ctx.write(" .");
        try ctx.write(attr.name);
        try ctx.write(" = ");
        try ctx.writeWithMappingFromByte(attr.value, attr.value_byte_offset, self);
    }

    try ctx.write(" })");
}

/// Write a regular HTML element: _zx.zx(.tag, .{ ... })
fn writeHtmlElement(self: *Ast, node: ts.Node, tag: []const u8, attributes: []const ZxAttribute, children: []const ts.Node, ctx: *TranspileContext) !void {
    try ctx.writeWithMappingFromByte("_zx.zx", node.startByte(), self);
    try ctx.write("(\n");

    ctx.indent_level += 1;
    try ctx.writeIndent();
    try ctx.writeWithMappingFromByte(".", node.startByte(), self);
    try ctx.write(tag);
    try ctx.write(",\n");

    // Write options struct
    try ctx.writeIndent();
    try ctx.write(".{\n");
    ctx.indent_level += 1;

    try writeAttributes(self, attributes, ctx);

    // Write children
    if (children.len > 0) {
        try ctx.writeIndent();
        try ctx.write(".children = &.{\n");
        ctx.indent_level += 1;

        for (children) |child| {
            const saved_len = ctx.output.items.len;
            try ctx.writeIndent();
            const had_output = try transpileChild(self, child, ctx);

            if (had_output) {
                try ctx.write(",\n");
            } else {
                ctx.output.shrinkRetainingCapacity(saved_len);
            }
        }

        ctx.indent_level -= 1;
        try ctx.writeIndent();
        try ctx.write("},\n");
    }

    ctx.indent_level -= 1;
    try ctx.writeIndent();
    try ctx.write("},\n");
    ctx.indent_level -= 1;

    try ctx.writeIndent();
    try ctx.write(")");
}

pub fn transpileChild(self: *Ast, node: ts.Node, ctx: *TranspileContext) error{OutOfMemory}!bool {
    // Returns true if any output was generated, false otherwise
    // zx_child can be: zx_element, zx_self_closing_element, zx_fragment, zx_expression_block, zx_text
    const child_count = node.childCount();
    if (child_count == 0) return false;

    // Get the actual child content (zx_child is a wrapper)
    var had_output = false;
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;

        switch (NodeKind.fromNode(child)) {
            .zx_text => {
                const text = try self.getNodeText(child);
                const trimmed = std.mem.trim(u8, text, &std.ascii.whitespace);
                if (trimmed.len == 0) continue;

                // JSX-like whitespace handling: preserve leading/trailing single space
                // when adjacent to expressions or other inline content
                const has_leading_ws = text.len > 0 and std.ascii.isWhitespace(text[0]);
                const has_trailing_ws = text.len > 0 and std.ascii.isWhitespace(text[text.len - 1]);

                try ctx.writeWithMappingFromByte("_zx.txt(\"", child.startByte(), self);
                if (has_leading_ws) try ctx.write(" ");
                try ctx.write(trimmed);
                if (has_trailing_ws) try ctx.write(" ");
                try ctx.write("\")");
                had_output = true;
            },
            .zx_expression_block => {
                try transpileExprBlock(self, child, ctx);
                had_output = true;
            },
            .zx_element => {
                try transpileFullElement(self, child, ctx, false);
                had_output = true;
            },
            .zx_self_closing_element => {
                try transpileSelfClosing(self, child, ctx, false);
                had_output = true;
            },
            .zx_fragment => {
                try transpileFragment(self, child, ctx, false);
                had_output = true;
            },
            else => {},
        }
    }
    return had_output;
}

pub fn transpileExprBlock(self: *Ast, node: ts.Node, ctx: *TranspileContext) error{OutOfMemory}!void {
    // zx_expression_block is: '{' expression '}'
    // We need to extract the expression and handle special cases
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_type = child.kind();

        // Handle token types (braces and parentheses)
        switch (SkipTokens.from(child_type)) {
            .open_brace, .close_brace => continue,
            .open_paren, .close_paren => {
                try ctx.write(child_type);
                continue;
            },
            .other => {},
        }

        // Handle control flow and special expressions
        switch (NodeKind.fromNode(child)) {
            .if_expression => {
                try transpileIf(self, child, ctx);
                continue;
            },
            .for_expression => {
                try transpileFor(self, child, ctx);
                continue;
            },
            .while_expression => {
                try transpileWhile(self, child, ctx);
                continue;
            },
            .switch_expression => {
                try transpileSwitch(self, child, ctx);
                continue;
            },
            .array_type => {
                try transpileFormat(self, child, ctx);
                continue;
            },
            else => {},
        }

        // Regular expression handling
        const expr_text = try self.getNodeText(child);
        const trimmed = std.mem.trim(u8, expr_text, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;

        if (trimmed[0] == '(') {
            // Component expression like {(component)}
            try ctx.writeWithMappingFromByte(trimmed, child.startByte(), self);
        } else {
            // Regular expression like {user.name}
            try ctx.writeWithMappingFromByte("_zx.txt(", child.startByte(), self);
            try ctx.write(trimmed);
            try ctx.write(")");
        }
    }
}

pub fn transpileFormat(self: *Ast, node: ts.Node, ctx: *TranspileContext) !void {
    // Format expression: {[expr:format]} is parsed as array_type
    // Extract expr and format from the source
    const text = try self.getNodeText(node);

    // Parse [expr:format] or [expr]
    if (text.len > 2 and text[0] == '[' and text[text.len - 1] == ']') {
        const inner = text[1 .. text.len - 1];
        const colon_idx = std.mem.indexOfScalar(u8, inner, ':');

        const expr = if (colon_idx) |idx| inner[0..idx] else inner;
        const format = if (colon_idx) |idx| inner[idx + 1 ..] else "d";

        try ctx.writeWithMappingFromByte("_zx.fmt(\"", node.startByte(), self);
        try ctx.write("{");
        try ctx.write(format);
        try ctx.write("}\", .{");
        try ctx.write(expr);
        try ctx.write("})");
    }
}

pub fn transpileIf(self: *Ast, node: ts.Node, ctx: *TranspileContext) !void {
    // if_expression: 'if' '(' condition ')' then_expr ['else' else_expr]
    var condition_text: ?[]const u8 = null;
    var then_node: ?ts.Node = null;
    var else_node: ?ts.Node = null;

    const child_count = node.childCount();
    var i: u32 = 0;
    var in_condition = false;
    var in_then = false;

    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_type = child.kind();

        if (std.mem.eql(u8, child_type, "if")) {
            in_condition = true;
        } else if (std.mem.eql(u8, child_type, "(") and in_condition) {
            // Start of condition
        } else if (std.mem.eql(u8, child_type, ")") and in_condition) {
            in_condition = false;
            in_then = true;
        } else if (std.mem.eql(u8, child_type, "else")) {
            in_then = false;
        } else if (in_condition and condition_text == null) {
            condition_text = try self.getNodeText(child);
        } else if (in_then and then_node == null) {
            then_node = child;
        } else if (!in_condition and !in_then and then_node != null) {
            else_node = child;
        }
    }

    const cond = condition_text orelse return;
    const then_n = then_node orelse return;

    try ctx.writeWithMappingFromByte("if", node.startByte(), self);
    try ctx.write(" ");

    // Write condition - ensure wrapped in parens
    const cond_trimmed = std.mem.trim(u8, cond, &std.ascii.whitespace);
    if (cond_trimmed.len > 0 and cond_trimmed[0] == '(' and cond_trimmed[cond_trimmed.len - 1] == ')') {
        try ctx.write(cond_trimmed);
    } else {
        try ctx.write("(");
        try ctx.write(cond_trimmed);
        try ctx.write(")");
    }
    try ctx.write(" ");

    // Handle then branch
    try transpileBranch(self, then_n, ctx);

    // Handle else branch
    if (else_node) |else_n| {
        try ctx.write(" else ");
        try transpileBranch(self, else_n, ctx);
    } else {
        try ctx.write(" else _zx.zx(.fragment, .{})");
    }
}

/// Helper to transpile if/else branches consistently
fn transpileBranch(self: *Ast, node: ts.Node, ctx: *TranspileContext) error{OutOfMemory}!void {
    switch (NodeKind.fromNode(node)) {
        .zx_block => try transpileBlock(self, node, ctx),
        .parenthesized_expression => {
            try ctx.write("_zx.zx(.fragment, .{ .children = &.{\n");
            try transpileExprBlock(self, node, ctx);
            try ctx.write(",},},)");
        },
        else => {
            try ctx.write("_zx.txt(");
            try ctx.writeWithMappingFromByte(try self.getNodeText(node), node.startByte(), self);
            try ctx.write(")");
        },
    }
}

pub fn transpileFor(self: *Ast, node: ts.Node, ctx: *TranspileContext) !void {
    // for_expression: 'for' '(' iterable ')' payload body
    var iterable_text: ?[]const u8 = null;
    var payload_text: ?[]const u8 = null;
    var body_node: ?ts.Node = null;

    const child_count = node.childCount();
    var i: u32 = 0;
    var seen_for = false;
    var seen_payload = false;

    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_type = child.kind();

        if (std.mem.eql(u8, child_type, "for")) {
            seen_for = true;
            continue;
        }

        // Skip parentheses
        if (SkipTokens.from(child_type) != .other) continue;

        if (seen_for and iterable_text == null) {
            iterable_text = try self.getNodeText(child);
            continue;
        }

        switch (NodeKind.fromNode(child)) {
            .payload => {
                payload_text = try self.getNodeText(child);
                seen_payload = true;
            },
            .zx_block, .parenthesized_expression => {
                if (seen_payload and body_node == null) {
                    body_node = child;
                }
            },
            else => {},
        }
    }

    if (iterable_text != null and payload_text != null and body_node != null) {
        // Generate: blk: { const __zx_children = _zx.getAllocator().alloc(...); for (...) |item, i| { ... }; break :blk __zx_children; }
        try ctx.writeWithMappingFromByte("blk", node.startByte(), self);
        try ctx.write(": {\n");

        ctx.indent_level += 1;
        try ctx.writeIndent();
        try ctx.write("const __zx_children = _zx.getAllocator().alloc(zx.Component, ");
        try ctx.write(iterable_text.?);
        try ctx.write(".len) catch unreachable;\n");

        try ctx.writeIndent();
        try ctx.writeWithMappingFromByte("for", node.startByte(), self);
        try ctx.write(" (");
        try ctx.write(iterable_text.?);
        try ctx.write(", 0..) |");

        // Extract just the variable name from payload (remove pipes)
        const payload = payload_text.?;
        const payload_clean = if (std.mem.startsWith(u8, payload, "|") and std.mem.endsWith(u8, payload, "|"))
            payload[1 .. payload.len - 1]
        else
            payload;

        try ctx.write(payload_clean);
        try ctx.write(", _zx_i| {\n");

        ctx.indent_level += 1;
        try ctx.writeIndent();
        try ctx.write("__zx_children[_zx_i] = ");
        try transpileBranch(self, body_node.?, ctx);
        try ctx.write(";\n");
        ctx.indent_level -= 1;

        try ctx.writeIndent();
        try ctx.write("}\n");

        try ctx.writeIndent();
        try ctx.write("break :blk _zx.zx(.fragment, .{ .children = __zx_children });\n");

        ctx.indent_level -= 1;
        try ctx.writeIndent();
        try ctx.write("}");
    }
}

pub fn transpileWhile(self: *Ast, node: ts.Node, ctx: *TranspileContext) !void {
    // while_expression: 'while' '(' condition ')' ':' '(' continue_expr ')' body
    var condition_text: ?[]const u8 = null;
    var continue_text: ?[]const u8 = null;
    var body_node: ?ts.Node = null;

    const child_count = node.childCount();
    var i: u32 = 0;

    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const field_name = node.fieldNameForChild(i);

        // Check for condition field
        if (field_name) |name| {
            if (std.mem.eql(u8, name, "condition")) {
                condition_text = try self.getNodeText(child);
                i += 1;
                continue;
            }
        }

        const child_kind = NodeKind.fromNode(child);
        switch (child_kind) {
            .assignment_expression => {
                continue_text = try self.getNodeText(child);
            },
            .zx_block => {
                body_node = child;
            },
            else => {},
        }
    }

    if (condition_text != null and body_node != null) {
        // Generate: blk: { var __zx_list = std.ArrayList(zx.Component).init(_zx.getAllocator()); while (cond) : (cont) { __zx_list.append(...); }; break :blk __zx_list.toOwnedSlice(); }
        try ctx.writeWithMappingFromByte("blk", node.startByte(), self);
        try ctx.write(": {\n");

        ctx.indent_level += 1;
        try ctx.writeIndent();
        try ctx.write("var __zx_list = @import(\"std\").ArrayList(zx.Component).empty;\n");

        try ctx.writeIndent();
        try ctx.writeWithMappingFromByte("while", node.startByte(), self);
        try ctx.write(" (");
        try ctx.write(condition_text.?);
        try ctx.write(")");

        if (continue_text) |cont| {
            try ctx.write(" : (");
            try ctx.write(std.mem.trim(u8, cont, &std.ascii.whitespace));
            try ctx.write(")");
        }

        try ctx.write(" {\n");

        ctx.indent_level += 1;
        try ctx.writeIndent();
        try ctx.write("__zx_list.append(_zx.getAllocator(), ");
        try transpileBlock(self, body_node.?, ctx);
        try ctx.write(") catch unreachable;\n");
        ctx.indent_level -= 1;

        try ctx.writeIndent();
        try ctx.write("}\n");

        try ctx.writeIndent();
        try ctx.write("break :blk _zx.zx(.fragment, .{ .children = __zx_list.items });\n");

        ctx.indent_level -= 1;
        try ctx.writeIndent();
        try ctx.write("}");
    }
}

pub fn transpileSwitch(self: *Ast, node: ts.Node, ctx: *TranspileContext) error{OutOfMemory}!void {
    // switch_expression: 'switch' '(' expr ')' '{' switch_case... '}'
    var switch_expr: ?[]const u8 = null;

    const child_count = node.childCount();
    var i: u32 = 0;
    var found_switch = false;

    // Find the switch expression
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_type = child.kind();

        if (std.mem.eql(u8, child_type, "switch")) {
            found_switch = true;
            continue;
        }

        // Skip delimiters
        if (SkipTokens.from(child_type) != .other) continue;

        if (found_switch and switch_expr == null) {
            switch_expr = try self.getNodeText(child);
            break;
        }
    }

    const expr = switch_expr orelse return;

    try ctx.writeWithMappingFromByte("switch", node.startByte(), self);
    try ctx.write(" (");
    try ctx.write(expr);
    try ctx.write(") {\n");

    ctx.indent_level += 1;

    // Parse switch cases
    i = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        if (NodeKind.fromNode(child) == .switch_case) {
            try transpileCase(self, child, ctx);
        }
    }

    ctx.indent_level -= 1;
    try ctx.writeIndent();
    try ctx.write("}");
}

pub fn transpileCase(self: *Ast, node: ts.Node, ctx: *TranspileContext) error{OutOfMemory}!void {
    // switch_case structure: pattern '=>' value
    try ctx.writeIndent();

    var pattern_node: ?ts.Node = null;
    var value_node: ?ts.Node = null;
    var seen_arrow = false;

    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;

        if (std.mem.eql(u8, child.kind(), "=>")) {
            seen_arrow = true;
        } else if (!seen_arrow and pattern_node == null) {
            pattern_node = child;
        } else if (seen_arrow and value_node == null) {
            value_node = child;
        }
    }

    if (pattern_node) |p| {
        try ctx.writeWithMappingFromByte(try self.getNodeText(p), p.startByte(), self);
        try ctx.write(" => ");
    }

    if (value_node) |v| {
        switch (NodeKind.fromNode(v)) {
            .zx_block => try transpileBlock(self, v, ctx),
            // Handle nested control flow expressions
            .if_expression => try transpileIf(self, v, ctx),
            .for_expression => try transpileFor(self, v, ctx),
            .while_expression => try transpileWhile(self, v, ctx),
            .switch_expression => try transpileSwitch(self, v, ctx),
            .parenthesized_expression => {
                // Value like `("Admin")` renders as _zx.txt("Admin")
                try ctx.writeWithMappingFromByte("_zx.txt", v.startByte(), self);
                try ctx.writeWithMappingFromByte(try self.getNodeText(v), v.startByte(), self);
            },
            else => try ctx.writeWithMappingFromByte(try self.getNodeText(v), v.startByte(), self),
        }
    }

    try ctx.write(",\n");
}

pub const ZxAttribute = struct {
    name: []const u8,
    value: []const u8,
    value_byte_offset: u32,
    is_builtin: bool,

    /// Check if any attributes in the list are regular (non-builtin)
    fn hasRegular(attrs: []const ZxAttribute) bool {
        for (attrs) |attr| {
            if (!attr.is_builtin) return true;
        }
        return false;
    }
};

/// Write builtin and regular attributes to the transpile context
fn writeAttributes(self: *Ast, attributes: []const ZxAttribute, ctx: *TranspileContext) !void {
    // Write builtin attributes first (like @allocator)
    for (attributes) |attr| {
        if (!attr.is_builtin) continue;
        try ctx.writeIndent();
        try ctx.write(".");
        try ctx.write(attr.name[1..]); // Skip @ prefix
        try ctx.write(" = ");
        try ctx.writeWithMappingFromByte(attr.value, attr.value_byte_offset, self);
        try ctx.write(",\n");
    }

    // Write regular attributes
    if (!ZxAttribute.hasRegular(attributes)) return;

    try ctx.writeIndent();
    try ctx.write(".attributes = &.{\n");
    ctx.indent_level += 1;

    for (attributes) |attr| {
        if (attr.is_builtin) continue;
        try ctx.writeIndent();
        try ctx.write(".{ .name = \"");
        try ctx.write(attr.name);
        try ctx.write("\", .value = ");
        try ctx.writeWithMappingFromByte(attr.value, attr.value_byte_offset, self);
        try ctx.write(" },\n");
    }

    ctx.indent_level -= 1;
    try ctx.writeIndent();
    try ctx.write("},\n");
}

pub fn parseAttribute(self: *Ast, node: ts.Node) !ZxAttribute {
    const node_kind = NodeKind.fromNode(node);

    // Handle nested attribute structure: zx_attribute contains zx_builtin_attribute or zx_regular_attribute
    const attr_node = switch (node_kind) {
        .zx_attribute => node.child(0) orelse return ZxAttribute{
            .name = "",
            .value = "\"\"",
            .value_byte_offset = node.startByte(),
            .is_builtin = false,
        },
        else => node,
    };

    // Use field names to get name and value directly
    const name_node = attr_node.childByFieldName("name");
    const value_node = attr_node.childByFieldName("value");

    const name = if (name_node) |n| try self.getNodeText(n) else "";
    const is_builtin = name.len > 0 and name[0] == '@';

    const value = if (value_node) |v| try getAttributeValue(self, v) else "\"\"";
    const value_offset = if (value_node) |v| v.startByte() else node.startByte();

    return ZxAttribute{
        .name = name,
        .value = value,
        .value_byte_offset = value_offset,
        .is_builtin = is_builtin,
    };
}

pub fn getAttributeValue(self: *Ast, node: ts.Node) ![]const u8 {
    const node_kind = NodeKind.fromNode(node);

    // For expression blocks, extract the inner expression using field name
    if (node_kind == .zx_expression_block) {
        const expr_node = node.childByFieldName("expression") orelse return try self.getNodeText(node);
        return try self.getNodeText(expr_node);
    }

    // For attribute values containing expression blocks, recurse
    if (node_kind == .zx_attribute_value) {
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            const child = node.child(i) orelse continue;
            if (NodeKind.fromNode(child) == .zx_expression_block) {
                return try getAttributeValue(self, child);
            }
            // Skip braces, return first non-brace content
            if (SkipTokens.from(child.kind()) == .other) {
                return try self.getNodeText(child);
            }
        }
    }

    return try self.getNodeText(node);
}
