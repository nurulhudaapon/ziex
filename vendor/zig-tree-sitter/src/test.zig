const build = @import("build");
const std = @import("std");
const testing = std.testing;
const ts = @import("root.zig");
const c = @import("tree-sitter-c");
const Language = ts.Language;

test "Language" {
    const language = Language.fromRaw(c.language());
    defer language.destroy();

    try testing.expectEqual(15, language.abiVersion());
    try testing.expect(language.semanticVersion() != null);
    try testing.expect(language.nodeKindCount() > 1);
    try testing.expect(language.fieldCount() > 1);
    try testing.expect(language.parseStateCount() > 1);
    try testing.expect(language.fieldIdForName("body") > 0);
    try testing.expect(language.fieldNameForId(1) != null);
    try testing.expectEqual(161, language.idForNodeKind("translation_unit", true));
    try testing.expectEqualStrings("identifier", language.nodeKindForId(1) orelse "");
    try testing.expect(language.nodeKindIsNamed(1));
    try testing.expect(language.nodeKindIsVisible(1));
    try testing.expect(!language.nodeKindIsSupertype(1));
    try testing.expect(language.nextState(1, 161) > 1);
    try testing.expect(!language.isWasm());

    const copy = language.dupe();
    try testing.expectEqual(language, copy);
    copy.destroy();
}

test "LookaheadIterator" {
    const language = Language.fromRaw(c.language());
    defer language.destroy();

    const state = language.nextState(1, 161);
    const lookahead = language.lookaheadIterator(state).?;
    defer lookahead.destroy();

    try testing.expectEqual(language, lookahead.language());
    try testing.expectEqual(0xFFFF, lookahead.currentSymbol());
    try testing.expectEqualStrings("ERROR", lookahead.currentSymbolName());

    try testing.expect(lookahead.next());
    try testing.expectEqual(160, lookahead.currentSymbol());
    try testing.expectEqualStrings("comment", lookahead.currentSymbolName());

    try testing.expect(lookahead.next());
    try testing.expectEqual(0, lookahead.currentSymbol());
    try testing.expectEqualStrings("end", lookahead.currentSymbolName());

    try testing.expect(!lookahead.next());
    try testing.expect(lookahead.resetState(state));

    try testing.expect(lookahead.next());
    try testing.expect(lookahead.reset(language, state));
}

test "Parser" {
    const language = Language.fromRaw(c.language());
    defer language.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(@ptrCast(language));

    try testing.expectEqual(language, parser.getLanguage());
    try testing.expectEqual(null, parser.getLogger().log);

    try testing.expectEqualSlices(ts.Range, &.{.{}}, parser.getIncludedRanges());
    try testing.expectError(error.IncludedRangesError, parser.setIncludedRanges(&.{ .{ .start_byte = 1 }, .{} }));

    // TODO: more tests
}

test "Tree" {
    const language = Language.fromRaw(c.language());
    defer language.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(@ptrCast(language));

    const tree = parser.parseString("int main() {}", null).?;
    defer tree.destroy();
    try testing.expectEqual(language, tree.getLanguage());
    try testing.expectEqual(13, tree.rootNode().endByte());
    try testing.expectEqual(3, tree.rootNodeWithOffset(3, .{ .row = 0, .column = 3 }).startByte());

    var ranges = try tree.getIncludedRanges(testing.allocator);
    var range: ts.Range = .{
        .start_point = .{ .row = 0, .column = 0 },
        .end_point = .{ .row = 0xFFFFFFFF, .column = 0xFFFFFFFF },
        .start_byte = 0,
        .end_byte = 0xFFFFFFFF,
    };
    try testing.expectEqualSlices(ts.Range, &.{range}, ranges);
    testing.allocator.free(ranges);

    const old_tree = tree.dupe();
    try testing.expect(tree != old_tree);
    defer old_tree.destroy();

    old_tree.edit(.{
        .start_byte = 0,
        .start_point = .{ .row = 0, .column = 0 },
        .old_end_byte = 13,
        .new_end_byte = 9,
        .old_end_point = .{ .row = 0, .column = 13 },
        .new_end_point = .{ .row = 0, .column = 9 },
    });
    const new_tree = parser.parseStringEncoding("main() {}", old_tree, .utf8).?;
    defer new_tree.destroy();
    range = .{
        .start_point = .{ .row = 0, .column = 0 },
        .end_point = .{ .row = 0, .column = 9 },
        .start_byte = 0,
        .end_byte = 9,
    };
    ranges = try old_tree.getChangedRanges(testing.allocator, new_tree);
    try testing.expectEqualSlices(ts.Range, &.{range}, ranges);
    testing.allocator.free(ranges);
}
//
test "TreeCursor" {
    const language = Language.fromRaw(c.language());
    defer language.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(@ptrCast(language));

    const tree = parser.parseStringEncoding("int main() {}", null, .utf8).?;
    defer tree.destroy();
    const root_node = tree.rootNode();

    var cursor = root_node.walk();
    defer cursor.destroy();

    var node = cursor.node();
    try testing.expect(node.eql(root_node));
    try testing.expectEqual(node, cursor.node());

    var copy = cursor.dupe();
    try testing.expect(cursor.id != copy.id);
    try testing.expectEqual(cursor.tree, copy.tree);

    cursor.resetTo(&copy);
    try testing.expectEqual(copy.node(), cursor.node());
    copy.destroy();

    try testing.expect(cursor.gotoFirstChild());
    try testing.expectEqualStrings("function_definition", cursor.node().kind());
    try testing.expectEqual(1, cursor.depth());

    try testing.expect(cursor.gotoLastChild());
    try testing.expectEqualStrings("compound_statement", cursor.node().kind());
    try testing.expectEqualStrings("body", cursor.fieldName().?);

    try testing.expect(cursor.gotoParent());
    try testing.expectEqualStrings("function_definition", cursor.node().kind());
    try testing.expectEqual(0, cursor.fieldId());

    try testing.expect(!cursor.gotoNextSibling());
    try testing.expect(!cursor.gotoPreviousSibling());

    cursor.gotoDescendant(2);
    try testing.expectEqual(2, cursor.descendantIndex());
    cursor.reset(root_node);

    try testing.expectEqual(0, cursor.gotoFirstChildForByte(1));
    try testing.expectEqual(1, cursor.gotoFirstChildForPoint(.{ .row = 0, .column = 5 }));
    try testing.expectEqualStrings("declarator", cursor.fieldName().?);
}

test "Node" {
    ts.setAllocator(testing.allocator);
    defer ts.setAllocator(null);

    const language = Language.fromRaw(c.language());
    defer language.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(@ptrCast(language));

    const tree = parser.parseStringEncoding("int main() {}", null, .utf8).?;
    defer tree.destroy();
    var node = tree.rootNode();

    try testing.expectEqual(tree, node.tree);
    try testing.expectEqual(tree.getLanguage(), node.getLanguage());

    try testing.expectEqual(161, node.kindId());
    try testing.expectEqual(161, node.grammarId());
    try testing.expectEqualStrings("translation_unit", node.kind());
    try testing.expectEqualStrings("translation_unit", node.grammarKind());

    try testing.expect(node.isNamed());
    try testing.expect(!node.isExtra());
    try testing.expect(!node.isError());
    try testing.expect(!node.isMissing());

    try testing.expectEqual(0, node.parseState());
    try testing.expectEqual(0, node.nextParseState());

    try testing.expectEqual(0, node.startByte());
    try testing.expectEqual(13, node.endByte());
    try testing.expectEqual(0, node.startPoint().column);
    try testing.expectEqual(13, node.endPoint().column);

    const range = node.range();
    try testing.expectEqual(0, range.start_byte);
    try testing.expectEqual(13, range.end_byte);
    try testing.expectEqual(0, range.start_point.column);
    try testing.expectEqual(13, range.end_point.column);

    try testing.expectEqual(1, node.childCount());
    try testing.expectEqual(1, node.namedChildCount());
    try testing.expectEqual(11, node.descendantCount());

    node = node.child(0).?;
    try testing.expectEqual(tree.rootNode(), node.parent());
    try testing.expectEqualStrings("function_declarator", node.namedChild(1).?.kind());
    try testing.expectEqual(null, node.childByFieldId(1));
    try testing.expectEqualStrings("primitive_type", node.childByFieldName("type").?.kind());

    try testing.expectEqualStrings("function_declarator", node.child(0).?.nextSibling().?.kind());
    try testing.expectEqualStrings("function_declarator", node.child(0).?.nextNamedSibling().?.kind());
    try testing.expectEqualStrings("function_declarator", node.child(2).?.prevSibling().?.kind());
    try testing.expectEqualStrings("function_declarator", node.child(2).?.prevNamedSibling().?.kind());

    try testing.expectEqual(node, tree.rootNode().childWithDescendant(node));
    try testing.expectEqualStrings("{", node.descendantForByteRange(11, 12).?.kind());
    try testing.expectEqualStrings("compound_statement", node.namedDescendantForByteRange(11, 12).?.kind());

    const points: [2]ts.Point = .{ .{ .row = 0, .column = 4 }, .{ .row = 0, .column = 8 } };
    try testing.expectEqualStrings("identifier", node.descendantForPointRange(points[0], points[1]).?.kind());
    try testing.expectEqualStrings("identifier", node.namedDescendantForPointRange(points[0], points[1]).?.kind());

    try testing.expectEqualStrings("body", node.fieldNameForChild(2).?);
    try testing.expectEqualStrings("body", node.fieldNameForNamedChild(2).?);

    const sexp = try node.toSexp(testing.allocator);
    defer testing.allocator.free(sexp);
    try testing.expectStringStartsWith(sexp, "(function_definition type:");

    const new_tree = tree.dupe();
    defer new_tree.destroy();
    const edit: ts.InputEdit = .{
        .start_byte = 0,
        .start_point = .{ .row = 0, .column = 0 },
        .old_end_byte = 13,
        .new_end_byte = 9,
        .old_end_point = .{ .row = 0, .column = 13 },
        .new_end_point = .{ .row = 0, .column = 9 },
    };
    new_tree.edit(edit);
    node = new_tree.rootNode();
    node.edit(edit);

    try testing.expect(node.hasChanges());
    try testing.expect(!node.hasError());
}

test "Query" {
    const language = Language.fromRaw(c.language());
    defer language.destroy();

    var error_offset: u32 = 0;
    try testing.expectError(error.InvalidNodeType, ts.Query.create(@ptrCast(language), "(foo) @foo", &error_offset));
    try testing.expectEqual(1, error_offset);

    const source =
        \\(identifier) @variable
        \\["{" "}" "(" ")"] @punctuation
        \\((identifier) @main
        \\ (#eq? @main "main"))
    ;
    var query = try ts.Query.create(@ptrCast(language), source, &error_offset);
    defer query.destroy();

    try testing.expectEqual(3, query.patternCount());
    try testing.expectEqual(3, query.captureCount());
    try testing.expectEqual(2, query.stringCount());

    try testing.expectEqual(23, query.startByteForPattern(1));
    try testing.expectEqual(54, query.endByteForPattern(1));

    try testing.expect(query.isPatternRooted(0));
    try testing.expect(!query.isPatternNonLocal(2));
    try testing.expect(!query.isPatternGuaranteedAtStep(9));

    try testing.expectEqualStrings("punctuation", query.captureNameForId(1).?);
    try testing.expectEqual(.one, query.captureQuantifierForId(0, 0).?);
    try testing.expectEqualStrings("main", query.stringValueForId(1).?);

    const steps: [4]ts.Query.PredicateStep = .{
        .{ .type = .string, .value_id = 0 },
        .{ .type = .capture, .value_id = 2 },
        .{ .type = .string, .value_id = 1 },
        .{ .type = .done, .value_id = 0 },
    };
    try testing.expectEqualSlices(ts.Query.PredicateStep, &steps, query.predicatesForPattern(2));
}

test "QueryCursor" {
    const language = Language.fromRaw(c.language());
    defer language.destroy();

    const source =
        \\(identifier) @variable
        \\["{" "}" "(" ")"] @punctuation
        \\((identifier) @main
        \\ (#eq? @main "main"))
    ;
    var error_offset: u32 = 0;
    var query = try ts.Query.create(@ptrCast(language), source, &error_offset);
    defer query.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(@ptrCast(language));

    const tree = parser.parseStringEncoding("int main() {}", null, .utf8).?;
    defer tree.destroy();

    const cursor = ts.QueryCursor.create();
    defer cursor.destroy();

    cursor.exec(query, tree.rootNode());

    try testing.expect(!cursor.didExceedMatchLimit());
    try testing.expectEqual(0xFFFFFFFF, cursor.getMatchLimit());

    var match = cursor.nextMatch().?;
    try testing.expectEqual(0, match.id);
    try testing.expectEqual(0, match.pattern_index);
    try testing.expectEqual(1, match.captures.len);
    try testing.expectEqual(0, match.captures[0].index);
    try testing.expectEqualStrings("identifier", match.captures[0].node.kind());

    _ = cursor.nextMatch();

    match = cursor.nextCapture().?[1];
    try testing.expectEqual(2, match.id);
    try testing.expectEqual(1, match.pattern_index);
    try testing.expectEqual(1, match.captures.len);
    try testing.expectEqual(1, match.captures[0].index);
    try testing.expectEqualStrings("(", match.captures[0].node.kind());
}

test "Wasm" {
    if (comptime !build.enable_wasm) return error.SkipZigTest;

    const engine = try ts.WasmEngine.init(null);
    defer engine.deinit();

    var error_message: []u8 = undefined;
    const store = ts.WasmStore.create(testing.allocator, engine, &error_message) catch |err| {
        std.log.err("{s}", .{error_message});
        testing.allocator.free(error_message);
        return err;
    };
    defer store.destroy();

    const wasm = @embedFile("tree-sitter-c.wasm");
    const language = store.loadLanguage(testing.allocator, "c", wasm, &error_message) catch |err| {
        std.log.err("{s}", .{error_message});
        testing.allocator.free(error_message);
        return err;
    };
    defer language.destroy();

    try testing.expect(language.isWasm());
    try testing.expectEqual(1, store.languageCount());

    const parser = ts.Parser.create();
    defer parser.destroy();

    try testing.expectError(error.IncompatibleLanguage, parser.setLanguage(language));
    parser.setWasmStore(store);
    defer _ = parser.takeWasmStore();
    try parser.setLanguage(language);

    const tree = parser.parseString("int main() {}", null).?;
    defer tree.destroy();

    try testing.expectEqualStrings("translation_unit", tree.rootNode().kind());

    try testing.expectError(error.ParseError, store.loadLanguage(testing.allocator, "c", "", &error_message));
    try testing.expectEqualStrings("failed to parse dylink section of Wasm module", error_message);
    testing.allocator.free(error_message);
}
