const Markdown = @This();

pub const NodeKind = enum {};

tree: *ts.Tree,
source: [:0]const u8,

pub fn parse(source: [:0]const u8) !Markdown {
    const parser = ts.Parser.create();
    parser.setLanguage(ts.Language.fromRaw(@import("tree_sitter_mdzx").language())) catch return error.LoadingLang;
    const tree = parser.parseString(source, null) orelse return error.ParseError;

    return Markdown{
        .tree = tree,
        .source = source,
    };
}

pub const RenderOptions = struct {
    const Mode = enum {
        zx,
        mdzx,
    };
    mode: RenderOptions.Mode,
    sourcemap: bool,
};

pub fn renderAlloc(self: *Markdown, allocator: std.mem.Allocator, options: RenderOptions) ![:0]const u8 {
    _ = options;
    _ = allocator;
    _ = self;
    return "Rendering not implemented yet";
}

const std = @import("std");
const ts = @import("tree_sitter");
