const testing = @import("std").testing;

const ts = @import("tree_sitter");
const root = @import("tree_sitter_zx");
const Language = ts.Language;
const Parser = ts.Parser;

test "can load grammar" {
    const parser = Parser.create();
    defer parser.destroy();

    const lang: *const ts.Language = @ptrCast(root.language());
    defer lang.destroy();

    try testing.expectEqual(void{}, parser.setLanguage(lang));
    try testing.expectEqual(lang, parser.getLanguage());
}
