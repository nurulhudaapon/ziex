const std = @import("std");
const ts = @import("tree_sitter");
const sourcemap = @import("sourcemap.zig");
const Parse = @import("Parse.zig");

const Ast = Parse.Parse;
const NodeKind = Parse.NodeKind;

pub const ClientComponentMetadata = struct {
    pub const Type = enum {
        csr, // Client-side React.js
        csz, // Client-side Zig
        pub fn from(value: []const u8) Type {
            const v = if (std.mem.startsWith(u8, value, ".")) value[1..value.len] else value;

            return std.meta.stringToEnum(Type, v) orelse {
                std.debug.print("Invalid rendering type: {s}\n", .{value});
                return .csz;
            };
        }
    };

    type: Type,
    name: []const u8,
    path: []const u8,
    id: []const u8,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, path: []const u8, component_type: Type, index: ?usize) !ClientComponentMetadata {
        const generated = generateComponentIdInner(name, path, index);
        const owned_id = try allocator.dupe(u8, generated.buf[0..generated.len]);

        const owned_path = try allocator.dupe(u8, path);
        return .{
            .type = component_type,
            .name = name,
            .path = owned_path,
            .id = owned_id,
        };
    }

    /// Generate a unique component ID based on name and path, with optional index postfix
    /// Format: zx-<md5hash>-<index> or zx-<md5hash> if index is null
    fn generateComponentIdInner(name: []const u8, path: []const u8, index: ?usize) struct { buf: [56]u8, len: usize } {
        var hasher = std.crypto.hash.Md5.init(.{});
        hasher.update(name);
        hasher.update(path);
        var digest: [16]u8 = undefined;
        hasher.final(&digest);

        // Buffer: "zx-" (3) + 32 hex chars + "-" (1) + max 20 digits = 56
        var result: [56]u8 = undefined;
        const prefix = "zx-";
        @memcpy(result[0..3], prefix);

        const hex_chars = "0123456789abcdef";
        for (digest, 0..) |byte, i| {
            result[3 + i * 2] = hex_chars[byte >> 4];
            result[3 + i * 2 + 1] = hex_chars[byte & 0x0f];
        }

        var len: usize = 35; // "zx-" + 32 hex chars

        // Append index as postfix if provided
        if (index) |idx| {
            result[len] = '-';
            len += 1;
            const idx_str = std.fmt.bufPrint(result[len..], "{d}", .{idx}) catch unreachable;
            len += idx_str.len;
        }

        return .{ .buf = result, .len = len };
    }
};

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
    /// Maps component name to its import path (from @jsImport)
    js_imports: std.StringHashMap([]const u8),
    /// Flag to track if we've done the pre-pass for @jsImport collection
    js_imports_collected: bool = false,
    /// The file path of the source file being transpiled (relative to cwd)
    file_path: ?[]const u8 = null,
    /// Counter for generating unique block labels and variable names (for nested loops)
    block_counter: u32 = 0,
    /// Flag to track if _zx has been initialized in the current scope (e.g., inside a return statement)
    zx_initialized: bool = false,
    /// Track client components (components with @rendering attribute)
    client_components: std.ArrayList(ClientComponentMetadata),
    allocator: std.mem.Allocator,

    pub const TranspileOptions = struct {
        sourcemap: bool,
        path: ?[]const u8,
    };

    pub fn init(allocator: std.mem.Allocator, source: []const u8, options: TranspileOptions) TranspileContext {
        return .{
            .output = std.array_list.Managed(u8).init(allocator),
            .source = source,
            .sourcemap_builder = sourcemap.Builder.init(allocator),
            .track_mappings = options.sourcemap,
            .js_imports = std.StringHashMap([]const u8).init(allocator),
            .file_path = options.path,
            .client_components = std.ArrayList(ClientComponentMetadata){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TranspileContext) void {
        self.output.deinit();
        self.sourcemap_builder.deinit();
        self.js_imports.deinit();
        self.client_components.deinit(self.allocator);
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

    fn writeM(self: *TranspileContext, bytes: []const u8, source_byte: u32, ast: *const Ast) !void {
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

    /// Get the next unique block index for generating unique labels/variable names
    pub fn nextBlockIndex(self: *TranspileContext) u32 {
        const idx = self.block_counter;
        self.block_counter += 1;
        return idx;
    }
};

/// Pre-pass to collect all @jsImport mappings from the entire AST
fn collectJsImports(self: *Ast, node: ts.Node, ctx: *TranspileContext) error{OutOfMemory}!void {
    const node_kind = NodeKind.fromNode(node);

    if (node_kind == .variable_declaration) {
        if (try extractJsImport(self, node)) |js_import| {
            try ctx.js_imports.put(js_import.name, js_import.path);
        }
    }

    // Recursively collect from children
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        try collectJsImports(self, child, ctx);
    }
}

pub fn transpileNode(self: *Ast, node: ts.Node, ctx: *TranspileContext) error{OutOfMemory}!void {
    const start_byte = node.startByte();
    const end_byte = node.endByte();
    const node_kind = NodeKind.fromNode(node);

    // On first call, do a pre-pass to collect all @jsImport mappings
    if (!ctx.js_imports_collected) {
        ctx.js_imports_collected = true;
        try collectJsImports(self, node, ctx);
    }

    // Check if this is a ZX block or return expression that needs special handling
    switch (node_kind) {
        .zx_block => {
            // For inline zx_blocks (not in return statements), just transpile the content
            try transpileBlock(self, node, ctx);
            return;
        },
        .variable_declaration => {
            // Check if this variable declaration contains @jsImport
            if (try extractJsImport(self, node)) |js_import| {
                // Store the mapping for later use
                try ctx.js_imports.put(js_import.name, js_import.path);
                // Comment out the entire declaration
                try ctx.writeM("// ", start_byte, self);
                if (start_byte < end_byte and end_byte <= self.source.len) {
                    try ctx.write(self.source[start_byte..end_byte]);
                }
                return;
            }
        },
        .return_expression => {
            const has_zx_block = findZxBlockInReturn(node) != null;

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
            try ctx.writeM(text, start_byte, self);
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
            try ctx.writeM(text, current_pos, self);
        }

        try transpileNode(self, child, ctx);
        current_pos = child_end;
    }

    if (current_pos < end_byte and end_byte <= self.source.len) {
        const text = self.source[current_pos..end_byte];
        try ctx.writeM(text, current_pos, self);
    }
}

const JsImportInfo = struct {
    name: []const u8,
    path: []const u8,
};

/// Extract @jsImport info from a variable declaration: const Name = @jsImport("path");
fn extractJsImport(self: *Ast, node: ts.Node) !?JsImportInfo {
    var component_name: ?[]const u8 = null;
    var import_path: ?[]const u8 = null;

    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_kind = NodeKind.fromNode(child);

        // Get the variable name (identifier)
        if (child_kind == .identifier) {
            component_name = try self.getNodeText(child);
        }

        // Check for @jsImport builtin
        if (child_kind == .builtin_function) {
            var is_js_import = false;
            const builtin_child_count = child.childCount();
            var j: u32 = 0;
            while (j < builtin_child_count) : (j += 1) {
                const builtin_child = child.child(j) orelse continue;
                const builtin_child_kind = NodeKind.fromNode(builtin_child);

                if (builtin_child_kind == .builtin_identifier) {
                    const ident = try self.getNodeText(builtin_child);
                    if (std.mem.eql(u8, ident, "@jsImport")) {
                        is_js_import = true;
                    }
                }

                // Extract the path from arguments
                if (is_js_import and builtin_child_kind == .arguments) {
                    const args_count = builtin_child.childCount();
                    var k: u32 = 0;
                    while (k < args_count) : (k += 1) {
                        const arg = builtin_child.child(k) orelse continue;
                        if (NodeKind.fromNode(arg) == .string) {
                            // Get string content (strip quotes)
                            const str_count = arg.childCount();
                            var m: u32 = 0;
                            while (m < str_count) : (m += 1) {
                                const str_child = arg.child(m) orelse continue;
                                if (NodeKind.fromNode(str_child) == .string_content) {
                                    import_path = try self.getNodeText(str_child);
                                    break;
                                }
                            }
                            // Fallback: strip quotes manually
                            if (import_path == null) {
                                const full = try self.getNodeText(arg);
                                if (full.len >= 2) {
                                    import_path = full[1 .. full.len - 1];
                                }
                            }
                            break;
                        }
                    }
                }
            }

            if (is_js_import) {
                if (component_name != null and import_path != null) {
                    return JsImportInfo{
                        .name = component_name.?,
                        .path = import_path.?,
                    };
                }
                // Has @jsImport but couldn't extract all info - still return something
                return JsImportInfo{
                    .name = component_name orelse "Unknown",
                    .path = import_path orelse "",
                };
            }
        }

        // Recursively check children
        if (try extractJsImport(self, child)) |info| {
            return info;
        }
    }
    return null;
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
                    try ctx.writeM("@import", node.startByte(), self);
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
    // Handle: return (<zx>...</zx>) or return ((<zx>...</zx>))
    // This should NOT initialize _zx here - that's done in the parent block
    const zx_block_node = findZxBlockInReturn(node);

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

                    try ctx.writeM("var", node.startByte(), self);
                    try ctx.write(" _zx = zx.");
                    if (allocator_value) |alloc| {
                        try ctx.write("allocInit(");
                        try ctx.write(alloc);
                        try ctx.write(")");
                    } else {
                        try ctx.write("init()");
                    }
                    try ctx.write(";\n");
                    // Mark that _zx is now initialized for nested ZX blocks
                    ctx.zx_initialized = true;
                    try ctx.writeIndent();
                    try ctx.writeM("return", node.startByte(), self);
                    try ctx.write(" ");
                    try transpileElement(self, child, ctx, true);
                    // Reset the flag after processing the return statement
                    ctx.zx_initialized = false;
                    return;
                },
                else => {},
            }
        }
    }
}

/// Find zx_block inside return expression (may be wrapped in parenthesized_expression)
fn findZxBlockInReturn(node: ts.Node) ?ts.Node {
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_kind = NodeKind.fromNode(child);

        if (child_kind == .zx_block) return child;
        if (child_kind == .parenthesized_expression) {
            if (findZxBlockInReturn(child)) |found| return found;
        }
    }
    return null;
}

pub fn transpileBlock(self: *Ast, node: ts.Node, ctx: *TranspileContext) !void {
    // This is for zx_block nodes found inside expressions (not top-level)
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_kind = NodeKind.fromNode(child);

        switch (child_kind) {
            .zx_element, .zx_self_closing_element, .zx_fragment => {
                // If _zx is already initialized (e.g., inside a return statement),
                // just transpile the element directly without wrapping
                if (ctx.zx_initialized) {
                    try transpileElement(self, child, ctx, false);
                    return;
                }

                // Otherwise, wrap in a self-contained labeled block with local _zx initialization
                // Get unique block index for this inline ZX expression
                const block_idx = ctx.nextBlockIndex();
                var idx_buf: [16]u8 = undefined;
                const idx_str = std.fmt.bufPrint(&idx_buf, "{d}", .{block_idx}) catch unreachable;

                // Check if element has @allocator attribute
                const allocator_value = try getAllocatorAttribute(self, child);

                // Generate: _zx_ele_blk_N: { var _zx = zx.init(); break :_zx_ele_blk_N _zx.ele(...); }
                try ctx.write("_zx_ele_blk_");
                try ctx.write(idx_str);
                try ctx.write(": {\n");

                ctx.indent_level += 1;
                try ctx.writeIndent();
                try ctx.write("var _zx = zx.");
                if (allocator_value) |alloc| {
                    try ctx.write("allocInit(");
                    try ctx.write(alloc);
                    try ctx.write(")");
                } else {
                    try ctx.write("init()");
                }
                try ctx.write(";\n");

                try ctx.writeIndent();
                try ctx.write("break :_zx_ele_blk_");
                try ctx.write(idx_str);
                try ctx.write(" ");
                try transpileElement(self, child, ctx, false);
                try ctx.write(";\n");

                ctx.indent_level -= 1;
                try ctx.writeIndent();
                try ctx.write("}");
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
        const child_kind = NodeKind.fromNode(child);

        // Regular elements like <div>...</div>)
        if (child_kind == .zx_start_tag) {
            const tag_children = child.childCount();
            var j: u32 = 0;
            while (j < tag_children) : (j += 1) {
                const attr = child.child(j) orelse continue;
                if (try checkAllocatorAttr(self, attr)) |value| return value;
            }
        }

        // Self-closing elements (like <Button @allocator={allocator} />)
        if (child_kind == .zx_attribute or child_kind == .zx_builtin_attribute) {
            if (try checkAllocatorAttr(self, child)) |value| return value;
        }
    }
    return null;
}

fn checkAllocatorAttr(self: *Ast, attr: ts.Node) !?[]const u8 {
    const attr_kind = NodeKind.fromNode(attr);
    if (attr_kind != .zx_attribute and attr_kind != .zx_builtin_attribute) return null;

    const actual_attr = if (attr_kind == .zx_attribute) attr.child(0) orelse return null else attr;

    const name_node = actual_attr.childByFieldName("name") orelse return null;
    const name = try self.getNodeText(name_node);

    if (std.mem.eql(u8, name, "@allocator")) {
        const value_node = actual_attr.childByFieldName("value") orelse return "allocator"; // TODO: need to catch and add to errors list in case of no value
        return try getAttributeValue(self, value_node);
    }
    return null;
}

pub fn transpileElement(self: *Ast, node: ts.Node, ctx: *TranspileContext, is_root: bool) !void {
    const node_kind = NodeKind.fromNode(node);
    switch (node_kind) {
        .zx_fragment => try transpileFragment(self, node, ctx, is_root),
        .zx_self_closing_element => try transpileSelfClosing(self, node, ctx, is_root),
        .zx_element => try transpileFullElement(self, node, ctx, is_root, false),
        else => unreachable,
    }
}

pub fn transpileFragment(self: *Ast, node: ts.Node, ctx: *TranspileContext, is_root: bool) !void {
    _ = is_root;

    // Collect all zx_child nodes from the fragment
    var children = std.ArrayList(ts.Node){};
    defer children.deinit(ctx.output.allocator);

    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        if (NodeKind.fromNode(child) == .zx_child) {
            try children.append(ctx.output.allocator, child);
        }
    }

    // Fragment is just like a regular element but with .fragment tag and no attributes
    try ctx.writeM("_zx.ele", node.startByte(), self);
    try ctx.write("(\n");

    ctx.indent_level += 1;
    try ctx.writeIndent();
    try ctx.write(".fragment,\n");

    try ctx.writeIndent();
    try ctx.write(".{\n");
    ctx.indent_level += 1;

    // Write children
    if (children.items.len > 0) {
        try ctx.writeIndent();
        try ctx.write(".children = &.{\n");
        ctx.indent_level += 1;

        for (children.items, 0..) |child, idx| {
            const saved_len = ctx.output.items.len;
            try ctx.writeIndent();
            const is_last_child = idx == children.items.len - 1;
            const had_output = try transpileChild(self, child, ctx, false, is_last_child);

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

pub fn isCustomComponent(tag: []const u8) bool {
    return tag.len > 0 and std.ascii.isUpper(tag[0]);
}

/// Check if element has @escaping={.raw} attribute (completely raw content, no processing)
fn hasRawEscaping(attributes: []const ZxAttribute) bool {
    for (attributes) |attr| {
        if (attr.is_builtin and std.mem.eql(u8, attr.name, "@escaping")) {
            if (std.mem.eql(u8, attr.value, ".raw")) return true;
        }
    }
    return false;
}

/// Check if element is a <pre> tag (preserve whitespace but still process children)
fn isPreElement(tag: []const u8) bool {
    return std.mem.eql(u8, tag, "pre");
}

/// Escape text for use in Zig string literal
fn escapeZigString(text: []const u8, ctx: *TranspileContext) !void {
    for (text) |c| {
        switch (c) {
            '\\' => try ctx.write("\\\\"),
            '"' => try ctx.write("\\\""),
            '\n' => try ctx.write("\\n"),
            '\r' => try ctx.write("\\r"),
            '\t' => try ctx.write("\\t"),
            else => try ctx.write(&[_]u8{c}),
        }
    }
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
        try writeCustomComponent(self, node, tag, attributes.items, &.{}, ctx);
    } else {
        try writeHtmlElement(self, node, tag, attributes.items, &.{}, ctx, false);
    }
}

pub fn transpileFullElement(self: *Ast, node: ts.Node, ctx: *TranspileContext, is_root: bool, parent_preserve_whitespace: bool) !void {
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
        try writeCustomComponent(self, node, tag, attributes.items, children.items, ctx);
        return;
    }

    // Check for @escaping={.raw} - completely raw content, no processing
    if (hasRawEscaping(attributes.items)) {
        // Find raw content between start tag and end tag
        var start_byte: u32 = 0;
        var end_byte: u32 = node.endByte();

        // Find start tag end and end tag start
        i = 0;
        while (i < child_count) : (i += 1) {
            const child = node.child(i) orelse continue;
            switch (NodeKind.fromNode(child)) {
                .zx_start_tag => start_byte = child.endByte(),
                .zx_end_tag => end_byte = child.startByte(),
                else => {},
            }
        }

        const raw_content = if (start_byte < end_byte and end_byte <= self.source.len)
            self.source[start_byte..end_byte]
        else
            "";
        try writeHtmlElementRaw(self, node, tag, attributes.items, raw_content, ctx);
        return;
    }

    // Check for <pre> tag - preserve whitespace but still process children normally
    // Also inherit preserve_whitespace from parent (e.g., nested elements inside <pre>)
    const preserve_whitespace = parent_preserve_whitespace or isPreElement(tag);

    // Regular HTML element (with optional whitespace preservation for <pre>)
    try writeHtmlElement(self, node, tag, attributes.items, children.items, ctx, preserve_whitespace);
}

/// Write a custom component: _zx.cmp(Component, .{ .prop = value }) or _zx.client(...) for CSR/CSZ
fn writeCustomComponent(self: *Ast, node: ts.Node, tag: []const u8, attributes: []const ZxAttribute, children: []const ts.Node, ctx: *TranspileContext) error{OutOfMemory}!void {
    // Check if this is a client-side rendered component (@rendering={.csr} or @rendering={.csz})
    var rendering_value: ?[]const u8 = null;
    for (attributes) |attr| {
        if (attr.is_builtin and std.mem.eql(u8, attr.name, "@rendering")) {
            rendering_value = attr.value;
            break;
        }
    }

    const is_csr = if (rendering_value) |rv| std.mem.eql(u8, rv, ".csr") else false;
    const is_csz = if (rendering_value) |rv| std.mem.eql(u8, rv, ".csz") else false;

    if (is_csr or is_csz) {
        var path_buf: [512]u8 = undefined;
        var full_path: []const u8 = undefined;

        if (is_csr) {
            // CSR: use current file's directory + @jsImport path
            const raw_path = ctx.js_imports.get(tag) orelse "unknown.tsx";

            // Get the directory of the current file
            if (ctx.file_path) |fp| {
                // Find the last slash to get the directory
                if (std.mem.lastIndexOfScalar(u8, fp, '/')) |last_slash| {
                    const dir = fp[0 .. last_slash + 1];
                    // Strip leading ./ from raw_path if present
                    const clean_path = if (std.mem.startsWith(u8, raw_path, "./"))
                        raw_path[2..]
                    else
                        raw_path;
                    const len = dir.len + clean_path.len;
                    if (len <= path_buf.len) {
                        @memcpy(path_buf[0..dir.len], dir);
                        @memcpy(path_buf[dir.len..][0..clean_path.len], clean_path);
                        full_path = path_buf[0..len];
                    } else {
                        full_path = raw_path;
                    }
                } else {
                    // No directory, just use the raw path with ./
                    if (std.mem.startsWith(u8, raw_path, "./")) {
                        full_path = raw_path;
                    } else {
                        const len = 2 + raw_path.len;
                        if (len <= path_buf.len) {
                            @memcpy(path_buf[0..2], "./");
                            @memcpy(path_buf[2..][0..raw_path.len], raw_path);
                            full_path = path_buf[0..len];
                        } else {
                            full_path = raw_path;
                        }
                    }
                }
            } else {
                // No file path, fallback to ./ + raw_path
                if (std.mem.startsWith(u8, raw_path, "./")) {
                    full_path = raw_path;
                } else {
                    const len = 2 + raw_path.len;
                    if (len <= path_buf.len) {
                        @memcpy(path_buf[0..2], "./");
                        @memcpy(path_buf[2..][0..raw_path.len], raw_path);
                        full_path = path_buf[0..len];
                    } else {
                        full_path = raw_path;
                    }
                }
            }
        } else {
            // CSZ: use file path with .zig extension (relative to cwd)
            if (ctx.file_path) |fp| {
                // Replace .zx extension with .zig
                if (std.mem.endsWith(u8, fp, ".zx")) {
                    const base_len = fp.len - 3;
                    const len = base_len + 4; // ".zig" is 4 chars
                    if (len <= path_buf.len) {
                        @memcpy(path_buf[0..base_len], fp[0..base_len]);
                        @memcpy(path_buf[base_len..][0..4], ".zig");
                        full_path = path_buf[0..len];
                    } else {
                        full_path = fp;
                    }
                } else {
                    full_path = fp;
                }
            } else {
                full_path = "unknown.zig";
            }
        }

        // Add to client components list (use current list length as stable index)
        const rendering_type = ClientComponentMetadata.Type.from(rendering_value orelse "csz");
        const component_index = ctx.client_components.items.len;
        const client_cmp = try ClientComponentMetadata.init(ctx.allocator, tag, full_path, rendering_type, component_index);
        try ctx.client_components.append(ctx.allocator, client_cmp);

        // Write _zx.client(.{ .name = "Name", .path = "path", .id = "id" }, .{ props })
        try ctx.writeM("_zx.client", node.startByte(), self);
        try ctx.write("(.{ .name = \"");
        try ctx.write(tag);
        try ctx.write("\", .path = \"");
        try ctx.write(full_path);
        try ctx.write("\", .id = \"");
        try ctx.write(client_cmp.id);
        try ctx.write("\" }, .{");

        // Write props (non-builtin attributes)
        var first_prop = true;
        for (attributes) |attr| {
            if (attr.is_builtin) continue;
            if (!first_prop) try ctx.write(",");
            first_prop = false;

            try ctx.write(" .");
            try ctx.write(attr.name);
            try ctx.write(" = ");
            // If value contains a zx_block, transpile it instead of writing raw text
            if (attr.zx_block_node) |zx_node| {
                try transpileBlock(self, zx_node, ctx);
            } else {
                try ctx.writeM(attr.value, attr.value_byte_offset, self);
            }
        }

        try ctx.write(" })");
    } else {
        // Regular cmp component
        try ctx.writeM("_zx.cmp", node.startByte(), self);
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
            // If value contains a zx_block, transpile it instead of writing raw text
            if (attr.zx_block_node) |zx_node| {
                try transpileBlock(self, zx_node, ctx);
            } else {
                try ctx.writeM(attr.value, attr.value_byte_offset, self);
            }
        }

        // Add children prop if there are children
        if (children.len > 0) {
            if (!first_prop) try ctx.write(",");
            try ctx.write(" .children = ");

            if (children.len == 1) {
                // Single child - transpile directly
                _ = try transpileChild(self, children[0], ctx, false, true);
            } else {
                // Multiple children - wrap in fragment
                try ctx.write("_zx.ele(.fragment, .{ .children = &.{");
                for (children, 0..) |child, idx| {
                    const saved_len = ctx.output.items.len;
                    const had_output = try transpileChild(self, child, ctx, false, idx == children.len - 1);
                    if (had_output) {
                        try ctx.write(", ");
                    } else {
                        ctx.output.shrinkRetainingCapacity(saved_len);
                    }
                }
                try ctx.write("} })");
            }
        }

        try ctx.write(" })");
    }
}

/// Write a regular HTML element: _zx.ele(.tag, .{ ... })
/// When preserve_whitespace is true (e.g. for <pre>), text nodes won't be trimmed
fn writeHtmlElement(self: *Ast, node: ts.Node, tag: []const u8, attributes: []const ZxAttribute, children: []const ts.Node, ctx: *TranspileContext, preserve_whitespace: bool) !void {
    try ctx.writeM("_zx.ele", node.startByte(), self);
    try ctx.write("(\n");

    ctx.indent_level += 1;
    try ctx.writeIndent();
    try ctx.writeM(".", node.startByte(), self);
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

        for (children, 0..) |child, idx| {
            const saved_len = ctx.output.items.len;
            try ctx.writeIndent();
            const is_last_child = idx == children.len - 1;
            const had_output = try transpileChild(self, child, ctx, preserve_whitespace, is_last_child);

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

/// Write a regular HTML element with raw (unprocessed) content: _zx.ele(.tag, .{ .children = &.{ _zx.txt("...") } })
fn writeHtmlElementRaw(self: *Ast, node: ts.Node, tag: []const u8, attributes: []const ZxAttribute, raw_content: []const u8, ctx: *TranspileContext) !void {
    try ctx.writeM("_zx.ele", node.startByte(), self);
    try ctx.write("(\n");

    ctx.indent_level += 1;
    try ctx.writeIndent();
    try ctx.writeM(".", node.startByte(), self);
    try ctx.write(tag);
    try ctx.write(",\n");

    // Write options struct
    try ctx.writeIndent();
    try ctx.write(".{\n");
    ctx.indent_level += 1;

    try writeAttributes(self, attributes, ctx);

    // Write raw content as single text child (preserve as-is)
    if (raw_content.len > 0) {
        try ctx.writeIndent();
        try ctx.write(".children = &.{\n");
        ctx.indent_level += 1;

        try ctx.writeIndent();
        try ctx.write("_zx.txt(\"");
        try escapeZigString(raw_content, ctx);
        try ctx.write("\"),\n");

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

/// Transpile a child node. When preserve_whitespace is true (e.g. inside <pre>),
/// text nodes are not trimmed and whitespace is preserved exactly.
/// is_last_child indicates if this is the last child in the parent (used for newline handling in <pre>).
pub fn transpileChild(self: *Ast, node: ts.Node, ctx: *TranspileContext, preserve_whitespace: bool, is_last_child: bool) error{OutOfMemory}!bool {
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

                if (preserve_whitespace) {
                    // For <pre> and similar: preserve whitespace exactly
                    // Add \n at end of each text node except the last child
                    if (text.len == 0) continue;

                    try ctx.writeM("_zx.txt(\"", child.startByte(), self);
                    try escapeZigString(text, ctx);
                    // Add newline at end unless this is the last child
                    if (!is_last_child) try ctx.write("\\n");
                    try ctx.write("\")");
                    had_output = true;
                } else {
                    // Normal mode: trim and normalize whitespace
                    const trimmed = std.mem.trim(u8, text, &std.ascii.whitespace);
                    if (trimmed.len == 0) continue;

                    // JSX-like whitespace handling: preserve leading/trailing single space
                    // when adjacent to expressions or other inline content
                    const has_leading_ws = text.len > 0 and std.ascii.isWhitespace(text[0]);
                    const has_trailing_ws = text.len > 0 and std.ascii.isWhitespace(text[text.len - 1]);

                    try ctx.writeM("_zx.txt(\"", child.startByte(), self);
                    if (has_leading_ws) try ctx.write(" ");
                    try escapeZigString(trimmed, ctx);
                    if (has_trailing_ws) try ctx.write(" ");
                    try ctx.write("\")");
                    had_output = true;
                }
            },
            .zx_expression_block => {
                try transpileExprBlock(self, child, ctx);
                had_output = true;
            },
            .zx_element => {
                // Pass preserve_whitespace to nested elements (e.g., elements inside <pre>)
                try transpileFullElement(self, child, ctx, false, preserve_whitespace);
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

        // Regular expression like {user.name}
        try ctx.writeM("_zx.expr(", child.startByte(), self);
        try ctx.writeM(trimmed, child.startByte(), self);
        try ctx.write(")");
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

        try ctx.writeM("_zx.fmt(\"", node.startByte(), self);
        try ctx.write("{");
        try ctx.write(format);
        try ctx.write("}\", .{");
        try ctx.write(expr);
        try ctx.write("})");
    }
}

pub fn transpileIf(self: *Ast, node: ts.Node, ctx: *TranspileContext) !void {
    // if_expression: 'if' '(' condition ')' [payload] then_expr ['else' else_expr]
    var condition_text: ?[]const u8 = null;
    var payload_text: ?[]const u8 = null;
    var then_node: ?ts.Node = null;
    var else_node: ?ts.Node = null;

    const child_count = node.childCount();
    var i: u32 = 0;
    var in_condition = false;
    var in_then = false;

    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_type = child.kind();
        const child_kind = NodeKind.fromNode(child);

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
        } else if (in_then and child_kind == .payload) {
            // Capture payload like |un|
            payload_text = try self.getNodeText(child);
        } else if (in_then and then_node == null) {
            then_node = child;
        } else if (!in_condition and !in_then and then_node != null) {
            else_node = child;
        }
    }

    const cond = condition_text orelse return;
    const then_n = then_node orelse return;

    try ctx.writeM("if", node.startByte(), self);
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

    // Write payload if present (e.g., |un|)
    if (payload_text) |payload| {
        try ctx.write(payload);
        try ctx.write(" ");
    }

    // Handle then branch
    try transpileBranch(self, then_n, ctx);

    // Handle else branch
    if (else_node) |else_n| {
        try ctx.write(" else ");
        try transpileBranch(self, else_n, ctx);
    } else {
        try ctx.write(" else _zx.ele(.fragment, .{})");
    }
}

/// Helper to transpile if/else branches consistently
fn transpileBranch(self: *Ast, node: ts.Node, ctx: *TranspileContext) error{OutOfMemory}!void {
    switch (NodeKind.fromNode(node)) {
        .zx_block => try transpileBlock(self, node, ctx),
        .if_expression => try transpileIf(self, node, ctx), // Handle else-if chains
        .parenthesized_expression => {
            try ctx.write("_zx.ele(.fragment, .{ .children = &.{\n");
            try transpileExprBlock(self, node, ctx);
            try ctx.write(",},},)");
        },
        else => {
            try ctx.write("_zx.txt(");
            try ctx.writeM(try self.getNodeText(node), node.startByte(), self);
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
        // Get unique index for this block to avoid conflicts with nested loops
        const block_idx = ctx.nextBlockIndex();
        var idx_buf: [16]u8 = undefined;
        const idx_str = std.fmt.bufPrint(&idx_buf, "{d}", .{block_idx}) catch unreachable;

        // Generate: _zx_for_blk_N: { const __zx_children_N = _zx.getAlloc().alloc(...); for (...) |item, i| { ... }; break :_zx_for_blk_N ...; }
        try ctx.writeM("_zx_for_blk_", node.startByte(), self);
        try ctx.write(idx_str);
        try ctx.write(": {\n");

        ctx.indent_level += 1;
        try ctx.writeIndent();
        try ctx.write("const __zx_children_");
        try ctx.write(idx_str);
        try ctx.write(" = _zx.getAlloc().alloc(zx.Component, ");
        try ctx.write(iterable_text.?);
        try ctx.write(".len) catch unreachable;\n");

        try ctx.writeIndent();
        try ctx.writeM("for", node.startByte(), self);
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
        try ctx.write(", _zx_i_");
        try ctx.write(idx_str);
        try ctx.write("| {\n");

        ctx.indent_level += 1;
        try ctx.writeIndent();
        try ctx.write("__zx_children_");
        try ctx.write(idx_str);
        try ctx.write("[_zx_i_");
        try ctx.write(idx_str);
        try ctx.write("] = ");
        try transpileBranch(self, body_node.?, ctx);
        try ctx.write(";\n");
        ctx.indent_level -= 1;

        try ctx.writeIndent();
        try ctx.write("}\n");

        try ctx.writeIndent();
        try ctx.write("break :_zx_for_blk_");
        try ctx.write(idx_str);
        try ctx.write(" _zx.ele(.fragment, .{ .children = __zx_children_");
        try ctx.write(idx_str);
        try ctx.write(" });\n");

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
        // Get unique index for this block to avoid conflicts with nested loops
        const block_idx = ctx.nextBlockIndex();
        var idx_buf: [16]u8 = undefined;
        const idx_str = std.fmt.bufPrint(&idx_buf, "{d}", .{block_idx}) catch unreachable;

        // Generate: _zx_whl_blk_N: { var __zx_list_N = std.ArrayList(zx.Component).init(_zx.getAlloc()); while (cond) : (cont) { __zx_list_N.append(...); }; break :_zx_whl_blk_N ...; }
        try ctx.writeM("_zx_whl_blk_", node.startByte(), self);
        try ctx.write(idx_str);
        try ctx.write(": {\n");

        ctx.indent_level += 1;
        try ctx.writeIndent();
        try ctx.write("var __zx_list_");
        try ctx.write(idx_str);
        try ctx.write(" = @import(\"std\").ArrayList(zx.Component).empty;\n");

        try ctx.writeIndent();
        try ctx.writeM("while", node.startByte(), self);
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
        try ctx.write("__zx_list_");
        try ctx.write(idx_str);
        try ctx.write(".append(_zx.getAlloc(), ");
        try transpileBlock(self, body_node.?, ctx);
        try ctx.write(") catch unreachable;\n");
        ctx.indent_level -= 1;

        try ctx.writeIndent();
        try ctx.write("}\n");

        try ctx.writeIndent();
        try ctx.write("break :_zx_whl_blk_");
        try ctx.write(idx_str);
        try ctx.write(" _zx.ele(.fragment, .{ .children = __zx_list_");
        try ctx.write(idx_str);
        try ctx.write(".items });\n");

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

    try ctx.writeM("switch", node.startByte(), self);
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
        try ctx.writeM(try self.getNodeText(p), p.startByte(), self);
        try ctx.write(" => ");
    }

    if (value_node) |v| {
        try transpileCaseValue(self, v, ctx);
    }

    try ctx.write(",\n");
}

/// Transpile switch case value, handling parenthesized expressions with nested control flow/zx
fn transpileCaseValue(self: *Ast, node: ts.Node, ctx: *TranspileContext) !void {
    const kind = NodeKind.fromNode(node);

    switch (kind) {
        .zx_block => try transpileBlock(self, node, ctx),
        .if_expression => try transpileIf(self, node, ctx),
        .for_expression => try transpileFor(self, node, ctx),
        .while_expression => try transpileWhile(self, node, ctx),
        .switch_expression => try transpileSwitch(self, node, ctx),
        .parenthesized_expression => {
            // Check if contains control flow or zx_block
            if (findSpecialChild(node)) |child| {
                try transpileCaseValue(self, child, ctx);
            } else {
                // Simple parenthesized expression like ("Admin")
                try ctx.writeM("_zx.txt", node.startByte(), self);
                try ctx.writeM(try self.getNodeText(node), node.startByte(), self);
            }
        },
        else => try ctx.writeM(try self.getNodeText(node), node.startByte(), self),
    }
}

/// Find control flow or zx_block inside a node
fn findSpecialChild(node: ts.Node) ?ts.Node {
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        switch (NodeKind.fromNode(child)) {
            .if_expression, .for_expression, .while_expression, .switch_expression, .zx_block => return child,
            else => {
                if (findSpecialChild(child)) |found| return found;
            },
        }
    }
    return null;
}

pub const ZxAttribute = struct {
    name: []const u8,
    value: []const u8,
    value_byte_offset: u32,
    is_builtin: bool,
    /// Optional zx_block node for attribute values that contain ZX elements
    zx_block_node: ?ts.Node = null,

    /// Check if any attributes in the list are regular (non-builtin)
    fn hasRegular(attrs: []const ZxAttribute) bool {
        for (attrs) |attr| {
            if (!attr.is_builtin) return true;
        }
        return false;
    }
};

/// Write builtin and regular attributes to the transpile context
fn writeAttributes(self: *Ast, attributes: []const ZxAttribute, ctx: *TranspileContext) error{OutOfMemory}!void {
    // Write builtin attributes first (like @allocator), but skip transpiler directives
    for (attributes) |attr| {
        if (!attr.is_builtin) continue;
        // Skip transpiler directives - not runtime attributes
        if (std.mem.eql(u8, attr.name, "@rendering")) continue;
        if (std.mem.eql(u8, attr.name, "@escaping")) continue;
        try ctx.writeIndent();
        try ctx.write(".");
        try ctx.write(attr.name[1..]); // Skip @ prefix
        try ctx.write(" = ");
        // If value contains a zx_block, transpile it instead of writing raw text
        if (attr.zx_block_node) |zx_node| {
            try transpileBlock(self, zx_node, ctx);
        } else {
            try ctx.writeM(attr.value, attr.value_byte_offset, self);
        }
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
        // If value contains a zx_block, transpile it instead of writing raw text
        if (attr.zx_block_node) |zx_node| {
            try transpileBlock(self, zx_node, ctx);
        } else {
            try ctx.writeM(attr.value, attr.value_byte_offset, self);
        }
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

    // Check if value contains a zx_block
    const zx_block_node = if (value_node) |v| findZxBlockInValue(v) else null;

    const value = if (value_node) |v| try getAttributeValue(self, v) else "\"\"";
    const value_offset = if (value_node) |v| v.startByte() else node.startByte();

    return ZxAttribute{
        .name = name,
        .value = value,
        .value_byte_offset = value_offset,
        .is_builtin = is_builtin,
        .zx_block_node = zx_block_node,
    };
}

/// Find a zx_block node within an attribute value (for values like attr={<div>...</div>})
fn findZxBlockInValue(node: ts.Node) ?ts.Node {
    const node_kind = NodeKind.fromNode(node);

    // Direct zx_block
    if (node_kind == .zx_block) {
        return node;
    }

    // Check children for zx_block
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        if (findZxBlockInValue(child)) |found| {
            return found;
        }
    }

    return null;
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
