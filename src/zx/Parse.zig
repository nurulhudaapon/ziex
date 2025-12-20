pub const Ast = @This();

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
    zx_builtin_name,
    zx_attribute_name,
    zx_attribute_value,
    zx_expression_block,
    zx_string_literal,
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

pub fn parse(allocator: std.mem.Allocator, source: []const u8) !Ast {
    const parser = ts.Parser.create();
    const lang = ts.Language.fromRaw(ts_zx.language());
    parser.setLanguage(lang) catch return error.LoadingLang;
    const tree = parser.parseString(source, null) orelse return error.ParseError;

    return Ast{
        .tree = tree,
        .source = source,
        .allocator = allocator,
    };
}

pub fn deinit(self: *Ast, _: std.mem.Allocator) void {
    self.tree.destroy();
}

pub const RenderResult = struct {
    output: []const u8,
    source_map: ?sourcemap.SourceMap = null,

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
            try Render.renderNode(self, root, &aw.writer);
            return RenderResult{ .output = try aw.toOwnedSlice() };
        },
        .zig => {
            var ctx = Transpile.TranspileContext.init(allocator, self.source, include_source_map);
            defer ctx.deinit();

            const root = self.tree.rootNode();
            try Transpile.transpileNode(self, root, &ctx);

            return RenderResult{
                .output = try ctx.output.toOwnedSlice(),
                .source_map = if (include_source_map) try ctx.finalizeSourceMap() else null,
            };
        },
    }
}

pub fn getNodeText(self: *Ast, node: ts.Node) ![]const u8 {
    const start = node.startByte();
    const end = node.endByte();
    if (start < end and end <= self.source.len) {
        return self.source[start..end];
    }
    return "";
}

pub fn getLineColumn(self: *const Ast, byte_offset: u32) struct { line: i32, column: i32 } {
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
