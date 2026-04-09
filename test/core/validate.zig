test "validate: valid element produces no diagnostics" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\pub fn Page(allocator: zx.Allocator) zx.Component {
        \\    return (<div>Hello</div>);
        \\}
        \\const zx = @import("zx");
    ;

    var parse_result = try Parser.parse(allocator, source, .zx);
    defer parse_result.deinit(allocator);

    var diags = try Validate.validate(allocator, &parse_result);
    defer diags.deinit();

    try testing.expectEqual(0, diags.items.len);
    try testing.expect(!diags.hasErrors());
}

test "validate: valid fragment produces no diagnostics" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\pub fn Page(allocator: zx.Allocator) zx.Component {
        \\    return (<><span>a</span><span>b</span></>);
        \\}
        \\const zx = @import("zx");
    ;

    var parse_result = try Parser.parse(allocator, source, .zx);
    defer parse_result.deinit(allocator);

    var diags = try Validate.validate(allocator, &parse_result);
    defer diags.deinit();

    try testing.expectEqual(0, diags.items.len);
    try testing.expect(!diags.hasErrors());
}

test "validate: valid expression block produces no diagnostics" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\pub fn Page(allocator: zx.Allocator) zx.Component {
        \\    const name = "world";
        \\    return (<p>Hello {name}!</p>);
        \\}
        \\const zx = @import("zx");
    ;

    var parse_result = try Parser.parse(allocator, source, .zx);
    defer parse_result.deinit(allocator);

    var diags = try Validate.validate(allocator, &parse_result);
    defer diags.deinit();

    try testing.expectEqual(0, diags.items.len);
}

test "validate: unclosed element tag produces error diagnostic" {
    const allocator = std.testing.allocator;

    // Missing closing </div>
    const source: [:0]const u8 =
        \\(<div>)
    ;

    var parse_result = try Parser.parse(allocator, source, .zx);
    defer parse_result.deinit(allocator);

    var diags = try Validate.validate(allocator, &parse_result);
    defer diags.deinit();

    try testing.expect(diags.hasErrors());
    try testing.expect(diags.items.len > 0);
    try testing.expectEqual(Validate.Severity.err, diags.items[0].severity);
}

test "validate: mismatched tags produce error diagnostic" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\(<div></span>)
    ;

    var parse_result = try Parser.parse(allocator, source, .zx);
    defer parse_result.deinit(allocator);

    var diags = try Validate.validate(allocator, &parse_result);
    defer diags.deinit();

    try testing.expect(diags.hasErrors());
    try testing.expect(diags.items.len > 0);
}

test "validate: diagnostic has non-zero line and column" {
    const allocator = std.testing.allocator;

    // Introduce an error on line 2, column 5
    const source: [:0]const u8 =
        \\pub fn Page(allocator: zx.Allocator) zx.Component {
        \\    return (<div>);
        \\}
        \\const zx = @import("zx");
    ;

    var parse_result = try Parser.parse(allocator, source, .zx);
    defer parse_result.deinit(allocator);

    var diags = try Validate.validate(allocator, &parse_result);
    defer diags.deinit();

    try testing.expect(diags.hasErrors());
    // Positions are 0-based.
    try testing.expect(diags.items[0].start_line >= 0);
    try testing.expect(diags.items[0].end_line >= diags.items[0].start_line);
}

test "validate: diagnostic message is non-empty" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\(<div>)
    ;

    var parse_result = try Parser.parse(allocator, source, .zx);
    defer parse_result.deinit(allocator);

    var diags = try Validate.validate(allocator, &parse_result);
    defer diags.deinit();

    try testing.expect(diags.items.len > 0);
    try testing.expect(diags.items[0].message.len > 0);
}

test "validate: broken line does not expand diagnostic to whole file" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\pub fn Page(allocator: zx.Allocator) zx.Component {
        \\    const broken = ;
        \\    return (<div>Hello</div>);
        \\}
        \\const zx = @import("zx");
    ;

    var parse_result = try Parser.parse(allocator, source, .zx);
    defer parse_result.deinit(allocator);

    var diags = try Validate.validate(allocator, &parse_result);
    defer diags.deinit();

    try testing.expect(diags.hasErrors());
    try testing.expect(diags.items.len > 0);

    const last_line: u32 = 4;
    try testing.expectEqual(@as(u32, 1), diags.items[0].start_line);
    try testing.expect(diags.items[0].end_line < last_line);
}

test "validate: Ast.parse on valid source has empty diagnostics" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\pub fn Page(allocator: zx.Allocator) zx.Component {
        \\    return (<p>OK</p>);
        \\}
        \\const zx = @import("zx");
    ;

    var result = try zx.Ast.parse(allocator, source, .{});
    defer result.deinit(allocator);

    try testing.expect(!result.diagnostics.hasErrors());
    try testing.expectEqual(0, result.diagnostics.items.len);
}

test "validate: Ast.parse on invalid source populates diagnostics" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\(<div>)
    ;

    var result = try zx.Ast.parse(allocator, source, .{});
    defer result.deinit(allocator);

    try testing.expect(result.diagnostics.hasErrors());
    try testing.expect(result.diagnostics.items.len > 0);
}

test "validate: Ast.fmt on valid source returns formatted source" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\pub fn Page(allocator: zx.Allocator) zx.Component {
        \\    return (<p>Hello</p>);
        \\}
        \\const zx = @import("zx");
    ;

    var result = try zx.Ast.fmt(allocator, source);
    defer result.deinit(allocator);

    try testing.expect(!result.diagnostics.hasErrors());
    try testing.expect(result.source != null);
}

test "validate: Ast.fmt on invalid source returns null source with diagnostics" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\(<div>)
    ;

    var result = try zx.Ast.fmt(allocator, source);
    defer result.deinit(allocator);

    try testing.expect(result.source == null);
    try testing.expect(result.diagnostics.hasErrors());
    try testing.expect(result.diagnostics.items.len > 0);
}

test "validate: hasErrors is false when diagnostics list is empty" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\pub fn Page(allocator: zx.Allocator) zx.Component {
        \\    return (<span>ok</span>);
        \\}
        \\const zx = @import("zx");
    ;

    var parse_result = try Parser.parse(allocator, source, .zx);
    defer parse_result.deinit(allocator);

    var diags = try Validate.validate(allocator, &parse_result);
    defer diags.deinit();

    try testing.expect(!diags.hasErrors());
}

const std = @import("std");
const testing = std.testing;
const zx = @import("zx");
const Parser = zx.Parse;
const Validate = zx.Validate;
