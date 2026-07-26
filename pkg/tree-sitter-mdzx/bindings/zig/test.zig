const testing = @import("std").testing;

const ts = @import("tree_sitter");
const root = @import("tree_sitter_mdzx");
const Language = ts.Language;
const Parser = ts.Parser;

test "can load block grammar" {
    const parser = Parser.create();
    defer parser.destroy();

    const lang: *const ts.Language = Language.fromRaw(root.language());
    defer lang.destroy();

    try testing.expectEqual(void{}, parser.setLanguage(lang));
    try testing.expectEqual(lang, parser.getLanguage());
}

test "can load inline grammar" {
    const parser = Parser.create();
    defer parser.destroy();

    const lang: *const ts.Language = Language.fromRaw(root.inlineLanguage());
    defer lang.destroy();

    try testing.expectEqual(void{}, parser.setLanguage(lang));
    try testing.expectEqual(lang, parser.getLanguage());
}
