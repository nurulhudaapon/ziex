pub const Ast = @This();

const NodeKind = enum {
    zx_block,
    zx_element,
    zx_self_closing_element,
    zx_fragment,
    zx_start_tag,
    zx_end_tag,
    zx_tag_name,
    zx_attribute,
    zx_builtin_attribute,
    zx_regular_attribute,
    zx_builtin_name,
    zx_attribute_name,
    zx_attribute_value,
    zx_expression_block,
    zx_string_literal,
    zx_child,
    zx_text,
    zx_js_import,
    identifier,
    string,
    variable_declaration,
    return_expression,

    fn fromString(s: []const u8) ?NodeKind {
        return std.meta.stringToEnum(NodeKind, s);
    }
};

tree: *ts.Tree,
source: []const u8,
allocator: std.mem.Allocator,

pub fn parse(allocator: std.mem.Allocator, source: []const u8) !Ast {
    const parser = ts.Parser.create();
    const lang = ts.Language.fromRaw(ts_zx.language());
    parser.setLanguage(lang) catch @panic("Failed to set language");
    const tree = parser.parseString(source, null) orelse return error.ParseError;

    return Ast{
        .tree = tree,
        .source = source,
        .allocator = allocator,
    };
}

pub fn deinit(self: *Ast, _: std.mem.Allocator) void {
    self.tree.destroy();
    // self.allocator.free(self.source);
}

pub const RenderResult = struct {
    output: []const u8,
    source_map: ?SourceMap = null,

    pub fn deinit(self: *RenderResult, allocator: std.mem.Allocator) void {
        allocator.free(self.output);
        if (self.source_map) |*sm| {
            sm.deinit(allocator);
        }
    }
};

pub const RenderMode = enum { zx, zig };

pub fn renderAlloc(self: *Ast, allocator: std.mem.Allocator, mode: RenderMode) ![]const u8 {
    const result = try self.renderAllocWithSourceMap(allocator, mode, false);
    defer if (result.source_map) |_| allocator.free(result.output);
    return if (result.source_map) |_| try allocator.dupe(u8, result.output) else result.output;
}

pub fn renderAllocWithSourceMap(
    self: *Ast,
    allocator: std.mem.Allocator,
    mode: RenderMode,
    include_source_map: bool,
) !RenderResult {
    switch (mode) {
        .zx => {
            var aw = std.io.Writer.Allocating.init(allocator);
            const root = self.tree.rootNode();
            try renderNode(self, root, &aw.writer);
            return RenderResult{ .output = try aw.toOwnedSlice() };
        },
        .zig => {
            var ctx = TranspileContext.init(allocator, self.source, include_source_map);
            defer ctx.deinit();

            const root = self.tree.rootNode();
            try self.transpileNode(root, &ctx);

            return RenderResult{
                .output = try ctx.output.toOwnedSlice(),
                .source_map = if (include_source_map) try ctx.finalizeSourceMap() else null,
            };
        },
    }
}

fn renderNode(self: *Ast, node: ts.Node, w: *std.io.Writer) !void {
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

        try renderNode(self, child, w);
        current_pos = child_end;
    }

    if (current_pos < end_byte and end_byte <= self.source.len) {
        try w.writeAll(self.source[current_pos..end_byte]);
    }
}

const TranspileContext = struct {
    output: std.array_list.Managed(u8),
    source: []const u8,
    mappings: std.array_list.Managed(SourceMapMapping),
    current_line: i32 = 0,
    current_column: i32 = 0,
    track_mappings: bool,
    indent_level: u32 = 0,

    fn init(allocator: std.mem.Allocator, source: []const u8, track_mappings: bool) TranspileContext {
        return .{
            .output = std.array_list.Managed(u8).init(allocator),
            .source = source,
            .mappings = std.array_list.Managed(SourceMapMapping).init(allocator),
            .track_mappings = track_mappings,
        };
    }

    fn deinit(self: *TranspileContext) void {
        self.output.deinit();
        self.mappings.deinit();
    }

    fn write(self: *TranspileContext, bytes: []const u8) !void {
        try self.output.appendSlice(bytes);
        self.updatePosition(bytes);
    }

    fn writeWithMapping(self: *TranspileContext, bytes: []const u8, source_line: i32, source_column: i32) !void {
        if (self.track_mappings and bytes.len > 0) {
            try self.mappings.append(.{
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

    fn finalizeSourceMap(self: *TranspileContext) !SourceMap {
        var mappings_str = std.array_list.Managed(u8).init(self.output.allocator);
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

const SourceMapMapping = struct {
    generated_line: i32,
    generated_column: i32,
    source_line: i32,
    source_column: i32,
};

pub const SourceMap = struct {
    mappings: []const u8,

    pub fn deinit(self: *SourceMap, allocator: std.mem.Allocator) void {
        allocator.free(self.mappings);
    }

    pub fn toJSON(self: SourceMap, allocator: std.mem.Allocator, source_file: []const u8) ![]const u8 {
        var json = std.array_list.Managed(u8).init(allocator);
        errdefer json.deinit();

        const writer = json.writer();
        try writer.writeAll("{\"version\":3,\"sources\":[\"");
        try writer.writeAll(source_file);
        try writer.writeAll("\"],\"mappings\":\"");
        try writer.writeAll(self.mappings);
        try writer.writeAll("\"}");

        return json.toOwnedSlice();
    }
};

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

fn transpileNode(self: *Ast, node: ts.Node, ctx: *TranspileContext) error{OutOfMemory}!void {
    const node_type = node.kind();
    const start_byte = node.startByte();
    const end_byte = node.endByte();
    const node_kind = NodeKind.fromString(node_type);

    // Check if this is a ZX block or return expression that needs special handling
    if (node_kind) |kind| {
        switch (kind) {
            .zx_block => {
                // For inline zx_blocks (not in return statements), just transpile the content
                try self.transpileZxBlockInline(node, ctx);
                return;
            },
            .return_expression => {
                const child_count = node.childCount();
                var has_zx_block = false;
                var i: u32 = 0;

                while (i < child_count) : (i += 1) {
                    const child = node.child(i) orelse continue;
                    const child_kind = NodeKind.fromString(child.kind());
                    if (child_kind == .zx_block) {
                        has_zx_block = true;
                        break;
                    }
                }

                if (has_zx_block) {
                    // Special handling for return (ZX)
                    try self.transpileReturnZx(node, ctx);
                    return;
                }
            },
            else => {},
        }
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

        try self.transpileNode(child, ctx);
        current_pos = child_end;
    }

    if (current_pos < end_byte and end_byte <= self.source.len) {
        const text = self.source[current_pos..end_byte];
        try ctx.writeWithMappingFromByte(text, current_pos, self);
    }
}

fn transpileReturnZx(self: *Ast, node: ts.Node, ctx: *TranspileContext) !void {
    // Handle: return (<zx>...</zx>)
    // This should NOT initialize _zx here - that's done in the parent block
    const child_count = node.childCount();
    var zx_block_node: ?ts.Node = null;

    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_type = child.kind();

        if (std.mem.eql(u8, child_type, "zx_block")) {
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
            const child_type = child.kind();
            const child_kind = NodeKind.fromString(child_type) orelse continue;

            switch (child_kind) {
                .zx_element, .zx_self_closing_element, .zx_fragment => {
                    // Check if we need to initialize _zx
                    const has_allocator = try self.hasAllocatorAttribute(child);

                    try ctx.writeWithMappingFromByte("var", node.startByte(), self);
                    try ctx.write(" _zx = zx.");
                    if (has_allocator) {
                        try ctx.write("initWithAllocator(allocator)");
                    } else {
                        try ctx.write("init()");
                    }
                    try ctx.write(";\n");
                    try ctx.writeIndent();
                    try ctx.writeWithMappingFromByte("return", node.startByte(), self);
                    try ctx.write(" ");
                    try self.transpileZxElement(child, ctx, true);
                    try ctx.write(";");
                    return;
                },
                else => {},
            }
        }
    }
}

fn transpileZxBlockInline(self: *Ast, node: ts.Node, ctx: *TranspileContext) !void {
    // This is for zx_block nodes found inside expressions (not top-level)
    // Extract the element and transpile it without initialization
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_type = child.kind();
        const child_kind = NodeKind.fromString(child_type) orelse continue;

        switch (child_kind) {
            .zx_element, .zx_self_closing_element, .zx_fragment => {
                try self.transpileZxElement(child, ctx, false);
                return;
            },
            else => {},
        }
    }
}

fn hasAllocatorAttribute(self: *Ast, node: ts.Node) !bool {
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_type = child.kind();
        const child_kind = NodeKind.fromString(child_type) orelse continue;

        switch (child_kind) {
            .zx_start_tag => {
                // Check attributes in start tag
                var j: u32 = 0;
                const tag_children = child.childCount();
                while (j < tag_children) : (j += 1) {
                    const attr = child.child(j) orelse continue;
                    const attr_type = attr.kind();
                    const attr_kind = NodeKind.fromString(attr_type) orelse continue;

                    switch (attr_kind) {
                        .zx_attribute, .zx_builtin_attribute => {
                            const attr_name = try self.getNodeText(attr);
                            if (std.mem.indexOf(u8, attr_name, "@allocator") != null) {
                                return true;
                            }
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }
    }
    return false;
}

fn transpileZxElement(self: *Ast, node: ts.Node, ctx: *TranspileContext, is_root: bool) !void {
    const node_type = node.kind();
    const node_kind = NodeKind.fromString(node_type);
    if (node_kind) |kind| {
        switch (kind) {
            .zx_fragment => try self.transpileZxFragment(node, ctx, is_root),
            .zx_self_closing_element => try self.transpileZxSelfClosing(node, ctx, is_root),
            .zx_element => try self.transpileZxFullElement(node, ctx, is_root),
            else => unreachable,
        }
    }
}

fn transpileZxFragment(self: *Ast, node: ts.Node, ctx: *TranspileContext, is_root: bool) !void {
    _ = is_root;
    _ = node;
    _ = self;
    _ = ctx;
    // TODO: Implement fragment transpilation
    // Fragments become anonymous containers
}

fn isCustomComponent(tag: []const u8) bool {
    return tag.len > 0 and std.ascii.isUpper(tag[0]);
}

fn transpileZxSelfClosing(self: *Ast, node: ts.Node, ctx: *TranspileContext, is_root: bool) !void {
    _ = is_root;

    // <tag attr1={val1} />  =>  _zx.zx(.tag, .{ .attributes = &.{...} })
    // or <Component props />  =>  _zx.lazy(Component, .{props})
    var tag_name: ?[]const u8 = null;
    var attributes = std.ArrayList(ZxAttribute){};
    defer attributes.deinit(ctx.output.allocator);

    // Parse the self-closing element
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_type = child.kind();
        const child_kind = NodeKind.fromString(child_type) orelse continue;

        switch (child_kind) {
            .zx_tag_name => {
                tag_name = try self.getNodeText(child);
            },
            .zx_attribute, .zx_builtin_attribute, .zx_regular_attribute => {
                const attr = try self.parseAttribute(child);
                if (attr.name.len > 0) { // Only add non-empty attributes
                    try attributes.append(ctx.output.allocator, attr);
                }
            },
            else => {},
        }
    }

    if (tag_name) |tag| {
        // Check if this is a custom component
        if (isCustomComponent(tag)) {
            // Custom component: _zx.lazy(Component, .{ .prop = value })
            try ctx.writeWithMappingFromByte("_zx.lazy", node.startByte(), self);
            try ctx.write("(");
            try ctx.write(tag);
            try ctx.write(", .{");

            // Write props
            for (attributes.items, 0..) |attr, idx| {
                if (attr.is_builtin) continue; // Skip builtins for custom components

                if (idx > 0) try ctx.write(", ");
                try ctx.write(" .");
                try ctx.write(attr.name);
                try ctx.write(" = ");
                try ctx.writeWithMappingFromByte(attr.value, attr.value_byte_offset, self);
            }

            try ctx.write(" })");
            return;
        }

        // Regular HTML element
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

        // Write builtin attributes first
        for (attributes.items) |attr| {
            if (!attr.is_builtin) continue;

            try ctx.writeIndent();
            try ctx.write(".");
            try ctx.write(attr.name[1..]); // Skip @ prefix
            try ctx.write(" = ");
            try ctx.writeWithMappingFromByte(attr.value, attr.value_byte_offset, self);
            try ctx.write(",\n");
        }

        // Write regular attributes
        var has_regular_attrs = false;
        for (attributes.items) |attr| {
            if (!attr.is_builtin) {
                has_regular_attrs = true;
                break;
            }
        }

        if (has_regular_attrs) {
            try ctx.writeIndent();
            try ctx.write(".attributes = &.{\n");

            ctx.indent_level += 1;
            for (attributes.items) |attr| {
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

        ctx.indent_level -= 1;
        try ctx.writeIndent();
        try ctx.write("},\n");
        ctx.indent_level -= 1;

        try ctx.writeIndent();
        try ctx.write(")");
    }
}

fn transpileZxFullElement(self: *Ast, node: ts.Node, ctx: *TranspileContext, is_root: bool) !void {
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
        const child_type = child.kind();
        const child_kind = NodeKind.fromString(child_type) orelse continue;

        switch (child_kind) {
            .zx_start_tag => {
                // Parse tag name and attributes from start tag
                const tag_children = child.childCount();
                var j: u32 = 0;
                while (j < tag_children) : (j += 1) {
                    const tag_child = child.child(j) orelse continue;
                    const tag_child_type = tag_child.kind();
                    const tag_child_kind = NodeKind.fromString(tag_child_type) orelse continue;

                    switch (tag_child_kind) {
                        .zx_tag_name => {
                            tag_name = try self.getNodeText(tag_child);
                        },
                        .zx_attribute, .zx_builtin_attribute, .zx_regular_attribute => {
                            const attr = try self.parseAttribute(tag_child);
                            if (attr.name.len > 0) { // Only add non-empty attributes
                                try attributes.append(ctx.output.allocator, attr);
                            }
                        },
                        else => {},
                    }
                }
            },
            .zx_child => {
                try children.append(ctx.output.allocator, child);
            },
            else => {},
        }
    }

    if (tag_name) |tag| {
        // Check if this is a custom component
        if (isCustomComponent(tag)) {
            // Custom component with children: _zx.lazy(Component, .{ .prop = value })
            // Note: children are ignored for custom components for now
            try ctx.writeWithMappingFromByte("_zx.lazy", node.startByte(), self);
            try ctx.write("(");
            try ctx.write(tag);
            try ctx.write(", .{");

            // Write props
            var first_prop = true;
            for (attributes.items) |attr| {
                if (attr.is_builtin) continue;

                if (!first_prop) try ctx.write(",");
                first_prop = false;

                try ctx.write(" .");
                try ctx.write(attr.name);
                try ctx.write(" = ");
                try ctx.writeWithMappingFromByte(attr.value, attr.value_byte_offset, self);
            }

            try ctx.write(" })");
            return;
        }

        // Regular HTML element
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

        // Write builtin attributes first (like @allocator)
        for (attributes.items) |attr| {
            if (!attr.is_builtin) continue;

            try ctx.writeIndent();
            try ctx.write(".");
            try ctx.write(attr.name[1..]); // Skip @ prefix
            try ctx.write(" = ");
            try ctx.writeWithMappingFromByte(attr.value, attr.value_byte_offset, self);
            try ctx.write(",\n");
        }

        // Write regular attributes
        var has_regular_attrs = false;
        for (attributes.items) |attr| {
            if (!attr.is_builtin) {
                has_regular_attrs = true;
                break;
            }
        }

        if (has_regular_attrs) {
            try ctx.writeIndent();
            try ctx.write(".attributes = &.{\n");

            ctx.indent_level += 1;
            for (attributes.items) |attr| {
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

        // Write children
        if (children.items.len > 0) {
            try ctx.writeIndent();
            try ctx.write(".children = &.{\n");

            ctx.indent_level += 1;
            for (children.items) |child| {
                const saved_len = ctx.output.items.len;
                try ctx.writeIndent();
                const had_output = try self.transpileZxChild(child, ctx);

                if (had_output) {
                    try ctx.write(",\n");
                } else {
                    // Remove the indent if nothing was written
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
}

fn transpileZxChild(self: *Ast, node: ts.Node, ctx: *TranspileContext) error{OutOfMemory}!bool {
    // Returns true if any output was generated, false otherwise
    // zx_child can be: zx_element, zx_self_closing_element, zx_fragment, zx_expression_block, zx_text
    const child_count = node.childCount();
    if (child_count == 0) return false;

    // Get the actual child content (zx_child is a wrapper)
    var had_output = false;
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_type = child.kind();
        const child_kind = NodeKind.fromString(child_type) orelse continue;

        switch (child_kind) {
            .zx_text => {
                const text = try self.getNodeText(child);
                const trimmed = std.mem.trim(u8, text, &std.ascii.whitespace);
                if (trimmed.len > 0) {
                    try ctx.writeWithMappingFromByte("_zx.txt(\"", child.startByte(), self);
                    try ctx.write(trimmed);
                    try ctx.write("\")");
                    had_output = true;
                }
            },
            .zx_expression_block => {
                try self.transpileZxExpressionBlock(child, ctx);
                had_output = true;
            },
            .zx_element => {
                try self.transpileZxFullElement(child, ctx, false);
                had_output = true;
            },
            .zx_self_closing_element => {
                try self.transpileZxSelfClosing(child, ctx, false);
                had_output = true;
            },
            .zx_fragment => {
                try self.transpileZxFragment(child, ctx, false);
                had_output = true;
            },
            else => {},
        }
    }
    return had_output;
}

fn transpileZxExpressionBlock(self: *Ast, node: ts.Node, ctx: *TranspileContext) !void {
    // zx_expression_block is: '{' expression '}'
    // We need to extract the expression and handle special cases
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_type = child.kind();

        // Skip braces
        if (std.mem.eql(u8, child_type, "{") or std.mem.eql(u8, child_type, "}")) {
            continue;
        }

        // Check for special expressions like if, for, switch
        if (std.mem.eql(u8, child_type, "if_expression")) {
            try self.transpileIfExpression(child, ctx);
        } else if (std.mem.eql(u8, child_type, "for_expression")) {
            try self.transpileForExpression(child, ctx);
        } else if (std.mem.eql(u8, child_type, "switch_expression")) {
            try self.transpileSwitchExpression(child, ctx);
        } else if (std.mem.eql(u8, child_type, "array_type")) {
            // This is a format expression: {[expr:format]}
            try self.transpileFormatExpression(child, ctx);
        } else {
            // Regular expression - check if it's a zx_block (component expression)
            const expr_text = try self.getNodeText(child);
            const trimmed = std.mem.trim(u8, expr_text, &std.ascii.whitespace);

            if (trimmed.len > 0 and trimmed[0] == '(') {
                // Likely a component expression like {(component)}
                try ctx.writeWithMappingFromByte(trimmed, child.startByte(), self);
            } else {
                // Regular expression like {user.name}
                try ctx.writeWithMappingFromByte("_zx.txt(", child.startByte(), self);
                try ctx.write(trimmed);
                try ctx.write(")");
            }
        }
    }
}

fn transpileFormatExpression(self: *Ast, node: ts.Node, ctx: *TranspileContext) !void {
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

fn transpileIfExpression(self: *Ast, node: ts.Node, ctx: *TranspileContext) !void {
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

    if (condition_text != null and then_node != null) {
        try ctx.writeWithMappingFromByte("if", node.startByte(), self);
        try ctx.write(" ");

        // Write condition - strip outer parens if present
        const cond = condition_text.?;
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
        const then_kind = NodeKind.fromString(then_node.?.kind());
        if (then_kind == .zx_block) {
            try self.transpileZxBlockInline(then_node.?, ctx);
        } else {
            try ctx.write("_zx.txt(");
            try ctx.writeWithMappingFromByte(try self.getNodeText(then_node.?), then_node.?.startByte(), self);
            try ctx.write(")");
        }

        if (else_node) |else_n| {
            try ctx.write(" else ");
            const else_kind = NodeKind.fromString(else_n.kind());
            if (else_kind == .zx_block) {
                try self.transpileZxBlockInline(else_n, ctx);
            } else {
                try ctx.write("_zx.txt(");
                try ctx.writeWithMappingFromByte(try self.getNodeText(else_n), else_n.startByte(), self);
                try ctx.write(")");
            }
        }
    }
}

fn transpileForExpression(self: *Ast, node: ts.Node, ctx: *TranspileContext) !void {
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
        } else if (seen_for and iterable_text == null and !std.mem.eql(u8, child_type, "(") and !std.mem.eql(u8, child_type, ")")) {
            iterable_text = try self.getNodeText(child);
        } else if (std.mem.eql(u8, child_type, "payload")) {
            payload_text = try self.getNodeText(child);
            seen_payload = true;
        } else if (seen_payload and body_node == null and std.mem.eql(u8, child_type, "zx_block")) {
            body_node = child;
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
        try self.transpileZxBlockInline(body_node.?, ctx);
        try ctx.write(";\n");
        ctx.indent_level -= 1;

        try ctx.writeIndent();
        try ctx.write("}\n");

        try ctx.writeIndent();
        try ctx.write("break :blk __zx_children;\n");
        ctx.indent_level -= 1;

        try ctx.writeIndent();
        try ctx.write("}");
    }
}

fn transpileSwitchExpression(self: *Ast, node: ts.Node, ctx: *TranspileContext) !void {
    // switch_expression: 'switch' '(' expr ')' '{' switch_case... '}'
    var switch_expr: ?[]const u8 = null;

    const child_count = node.childCount();
    var i: u32 = 0;
    var found_expr = false;

    // Find the switch expression
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_type = child.kind();

        if (std.mem.eql(u8, child_type, "switch")) {
            found_expr = true;
        } else if (found_expr and !std.mem.eql(u8, child_type, "(") and !std.mem.eql(u8, child_type, ")") and !std.mem.eql(u8, child_type, "{")) {
            switch_expr = try self.getNodeText(child);
            break;
        }
    }

    if (switch_expr) |expr| {
        try ctx.writeWithMappingFromByte("switch", node.startByte(), self);
        try ctx.write(" (");
        try ctx.write(expr);
        try ctx.write(") {\n");

        ctx.indent_level += 1;

        // Parse switch cases
        i = 0;
        while (i < child_count) : (i += 1) {
            const child = node.child(i) orelse continue;
            const child_type = child.kind();

            if (std.mem.eql(u8, child_type, "switch_case")) {
                try self.transpileSwitchCase(child, ctx);
            }
        }

        ctx.indent_level -= 1;
        try ctx.writeIndent();
        try ctx.write("}");
    }
}

fn transpileSwitchCase(self: *Ast, node: ts.Node, ctx: *TranspileContext) !void {
    // switch_case structure: pattern '=>' value
    // pattern is field_expression (e.g., .admin)
    // value is zx_block or other expression

    try ctx.writeIndent();

    var pattern_node: ?ts.Node = null;
    var value_node: ?ts.Node = null;
    var seen_arrow = false;

    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_type = child.kind();

        if (std.mem.eql(u8, child_type, "=>")) {
            seen_arrow = true;
        } else if (!seen_arrow and pattern_node == null) {
            pattern_node = child;
        } else if (seen_arrow and value_node == null) {
            value_node = child;
        }
    }

    if (pattern_node) |p| {
        const pattern_text = try self.getNodeText(p);
        try ctx.writeWithMappingFromByte(pattern_text, p.startByte(), self);
        try ctx.write(" => ");
    }

    if (value_node) |v| {
        const value_kind = NodeKind.fromString(v.kind());

        if (value_kind == .zx_block) {
            try self.transpileZxBlockInline(v, ctx);
        } else {
            const value_text = try self.getNodeText(v);
            try ctx.writeWithMappingFromByte(value_text, v.startByte(), self);
        }
    }

    try ctx.write(",\n");
}

const ZxAttribute = struct {
    name: []const u8,
    value: []const u8,
    value_byte_offset: u32,
    is_builtin: bool,
};

fn parseAttribute(self: *Ast, node: ts.Node) !ZxAttribute {
    var name: ?[]const u8 = null;
    var value: ?[]const u8 = null;
    var value_offset: u32 = 0;
    var is_builtin = false;

    const node_type = node.kind();
    const node_kind = NodeKind.fromString(node_type);

    // Handle nested attribute structure: zx_attribute contains zx_builtin_attribute or zx_regular_attribute
    if (node_kind) |kind| {
        switch (kind) {
            .zx_attribute => {
                // Get the actual attribute child
                const child_count = node.childCount();
                if (child_count > 0) {
                    const actual_attr = node.child(0) orelse return ZxAttribute{
                        .name = "",
                        .value = "\"\"",
                        .value_byte_offset = node.startByte(),
                        .is_builtin = false,
                    };
                    return try self.parseAttribute(actual_attr);
                }
            },
            else => {},
        }
    }

    // Parse builtin or regular attribute directly
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_type = child.kind();
        const child_kind = NodeKind.fromString(child_type) orelse continue;

        switch (child_kind) {
            .zx_attribute_name, .zx_builtin_name => {
                name = try self.getNodeText(child);
                is_builtin = std.mem.startsWith(u8, name.?, "@");
            },
            .zx_attribute_value => {
                value_offset = child.startByte();
                value = try self.getAttributeValue(child);
            },
            else => {},
        }
    }

    return ZxAttribute{
        .name = name orelse "",
        .value = value orelse "\"\"",
        .value_byte_offset = value_offset,
        .is_builtin = is_builtin,
    };
}

fn getAttributeValue(self: *Ast, node: ts.Node) ![]const u8 {
    const node_type = node.kind();
    const node_kind = NodeKind.fromString(node_type);
    const child_count = node.childCount();

    // Check if it's a zx_expression_block or zx_attribute_value
    if (node_kind) |kind| {
        switch (kind) {
            .zx_expression_block, .zx_attribute_value => {
                var i: u32 = 0;
                while (i < child_count) : (i += 1) {
                    const child = node.child(i) orelse continue;
                    const child_type = child.kind();

                    // Skip braces
                    if (std.mem.eql(u8, child_type, "{") or std.mem.eql(u8, child_type, "}")) {
                        continue;
                    }

                    const child_kind = NodeKind.fromString(child_type);
                    if (child_kind) |ck| {
                        switch (ck) {
                            .zx_expression_block => {
                                // Recursively get the expression inside
                                return try self.getAttributeValue(child);
                            },
                            else => {
                                // This is the expression - return just the expression text
                                return try self.getNodeText(child);
                            },
                        }
                    } else {
                        // This is the expression - return just the expression text
                        return try self.getNodeText(child);
                    }
                }
            },
            else => {},
        }
    }

    // Otherwise it's a string literal
    return try self.getNodeText(node);
}

fn getNodeText(self: *Ast, node: ts.Node) ![]const u8 {
    const start = node.startByte();
    const end = node.endByte();
    if (start < end and end <= self.source.len) {
        return self.source[start..end];
    }
    return "";
}

fn getLineColumn(self: *const Ast, byte_offset: u32) struct { line: i32, column: i32 } {
    var line: i32 = 0;
    var column: i32 = 0;
    var i: u32 = 0;

    while (i < byte_offset and i < self.source.len) : (i += 1) {
        if (self.source[i] == '\n') {
            line += 1;
            column = 0;
        } else {
            column += 1;
        }
    }

    return .{ .line = line, .column = column };
}

const std = @import("std");
const ts = @import("tree_sitter");
const ts_zx = @import("tree_sitter_zx");
