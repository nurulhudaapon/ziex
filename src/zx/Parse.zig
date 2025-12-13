pub const Ast = @This();

tree: *ts.Tree,
source: []const u8,
allocator: std.mem.Allocator,

pub fn parse(allocator: std.mem.Allocator, source: []const u8) !Ast {
    const parser = ts.Parser.create();
    const lang = ts.Language.fromRaw(ts_zx.language());
    parser.setLanguage(lang) catch @panic("Failed to set language");
    const tree = parser.parseString(source, null) orelse return error.ParseError;

    // Store a copy of the source
    const source_copy = try allocator.dupe(u8, source);

    return Ast{
        .tree = tree,
        .source = source_copy,
        .allocator = allocator,
    };
}

pub fn deinit(self: *Ast, _: std.mem.Allocator) void {
    self.tree.destroy();
    self.allocator.free(self.source);
}

const RenderMode = enum { zx, zig };
pub fn renderAlloc(self: *Ast, allocator: std.mem.Allocator, mode: RenderMode) ![]const u8 {
    var aw = std.io.Writer.Allocating.init(allocator);
    switch (mode) {
        .zx => try renderZx(self, &aw.writer),
        .zig => try renderZig(self, &aw.writer),
    }

    return aw.toOwnedSlice();
}

fn renderZx(self: *Ast, w: *std.io.Writer) !void {
    const root = self.tree.rootNode();
    try renderNode(self, root, w);
}

fn renderZig(self: *Ast, w: *std.io.Writer) !void {
    // TODO: Implement proper transpilation to Zig
    // For now, just output a placeholder
    const root = self.tree.rootNode();
    try w.print("// TODO: Transpile to Zig\n", .{});
    try renderNode(self, root, w);
}

fn renderNode(self: *Ast, node: ts.Node, w: *std.io.Writer) !void {
    // Get the byte range for this node
    const start_byte = node.startByte();
    const end_byte = node.endByte();

    // If node has no children, write its text content
    const child_count = node.childCount();
    if (child_count == 0) {
        if (start_byte < end_byte and end_byte <= self.source.len) {
            const text = self.source[start_byte..end_byte];
            try w.writeAll(text);
        }
        return;
    }

    // If node has children, recursively render them
    var current_pos = start_byte;
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        const child_start = child.startByte();
        const child_end = child.endByte();

        // Write any text between current position and child start
        if (current_pos < child_start and child_start <= self.source.len) {
            const between_text = self.source[current_pos..child_start];
            try w.writeAll(between_text);
        }

        // Render the child node
        try renderNode(self, child, w);

        // Update current position
        current_pos = child_end;
    }

    // Write any remaining text after the last child
    if (current_pos < end_byte and end_byte <= self.source.len) {
        const remaining_text = self.source[current_pos..end_byte];
        try w.writeAll(remaining_text);
    }
}

const std = @import("std");
const ts = @import("tree_sitter");
const ts_zx = @import("tree_sitter_zx");
