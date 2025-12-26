pub const Parse = @This();

pub const NodeKind = enum {
    /// (<..>..</..>)
    zx_block,
    /// <tag attr1={val1} />
    zx_element,
    /// <tag attr1={val1} />
    zx_self_closing_element,
    /// <>..</>
    zx_fragment,
    /// <div>
    zx_start_tag,
    /// </div>
    zx_end_tag,
    /// <|div|>
    zx_tag_name,
    /// attrexpr={val1}
    /// attrstr="test"
    /// attrbool
    zx_attribute,
    /// @attr
    zx_builtin_attribute,
    zx_regular_attribute,
    /// {class} shorthand for class={class}
    zx_shorthand_attribute,
    /// @{allocator} shorthand for @allocator={allocator}
    zx_builtin_shorthand_attribute,
    zx_builtin_name,
    zx_attribute_name,
    zx_attribute_value,
    zx_expression_block,
    zx_string_literal,
    zx_template_string,
    zx_template_content,
    zx_template_substitution,
    zx_child,
    zx_text,
    zx_js_import,

    // Zig Related Nodes
    builtin_function,
    builtin_identifier,
    arguments,
    string_content,
    parenthesized_expression,

    identifier,
    field_expression,
    string,
    variable_declaration,
    return_expression,

    // Control Flow Expressions
    if_expression,
    for_expression,
    while_expression,
    switch_expression,
    switch_case,
    payload,
    array_type,
    assignment_expression,
    multiline_string,

    /// Anonymous/unrecognized node kind
    anon,

    fn fromString(s: []const u8) NodeKind {
        return std.meta.stringToEnum(NodeKind, s) orelse .anon;
    }

    pub fn fromNode(node: ?ts.Node) NodeKind {
        if (node == null) return .anon;
        return fromString(node.?.kind());
    }
};

tree: *ts.Tree,
source: []const u8,
allocator: std.mem.Allocator,

pub fn parse(allocator: std.mem.Allocator, source: []const u8) !Parse {
    const parser = ts.Parser.create();
    const lang = ts.Language.fromRaw(ts_zx.language());
    parser.setLanguage(lang) catch return error.LoadingLang;
    const tree = parser.parseString(source, null) orelse return error.ParseError;

    return Parse{
        .tree = tree,
        .source = source,
        .allocator = allocator,
    };
}

pub fn deinit(self: *Parse, _: std.mem.Allocator) void {
    self.tree.destroy();
}

pub const ClientComponentMetadata = Transpile.ClientComponentMetadata;
pub const RenderResult = struct {
    source: []const u8,
    sourcemap: ?sourcemap.SourceMap = null,
    client_components: []const Transpile.ClientComponentMetadata,

    pub fn deinit(self: *RenderResult, allocator: std.mem.Allocator) void {
        allocator.free(self.source);
        if (self.sourcemap) |*sm| {
            sm.deinit(allocator);
        }
        for (self.client_components.items) |*component| {
            allocator.free(component.name);
            allocator.free(component.path);
            allocator.free(component.id);
        }
        self.client_components.deinit(allocator);
    }
};

pub const RenderOptions = struct {
    pub const RenderMode = enum { zx, zig };
    mode: RenderMode,
    sourcemap: bool,
    path: ?[]const u8,
};

pub fn renderAlloc(
    self: *Parse,
    allocator: std.mem.Allocator,
    options: RenderOptions,
) !RenderResult {
    switch (options.mode) {
        .zx => {
            var aw = std.io.Writer.Allocating.init(allocator);
            const root = self.tree.rootNode();
            try Render.renderNode(self, root, &aw.writer);
            return RenderResult{ .source = try aw.toOwnedSlice(), .client_components = &.{} };
        },
        .zig => {
            var ctx = Transpile.TranspileContext.init(allocator, self.source, .{ .sourcemap = options.sourcemap, .path = options.path });
            defer ctx.deinit();

            const root = self.tree.rootNode();
            try Transpile.transpileNode(self, root, &ctx);

            return RenderResult{
                .source = try ctx.output.toOwnedSlice(),
                .sourcemap = if (options.sourcemap) try ctx.finalizeSourceMap() else null,
                .client_components = try ctx.client_components.toOwnedSlice(allocator),
            };
        },
    }
}

pub fn getNodeText(self: *Parse, node: ts.Node) ![]const u8 {
    const start = node.startByte();
    const end = node.endByte();
    if (start < end and end <= self.source.len) {
        return self.source[start..end];
    }
    return "";
}

pub fn getLineColumn(self: *const Parse, byte_offset: u32) struct { line: i32, column: i32 } {
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
const sourcemap = @import("sourcemap.zig");
const Render = @import("Render.zig");
const Transpile = @import("Transpile.zig");
