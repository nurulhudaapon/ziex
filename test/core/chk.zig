test "valid element" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\pub fn Page(allocator: zx.Allocator) zx.Component {
        \\    return (<div>Hello</div>);
        \\}
        \\const zx = @import("zx");
    ;

    var parse_result = try Parser.parse(allocator, source, .zx);
    defer parse_result.deinit(allocator);

    var diags = try check.validate(allocator, &parse_result);
    defer diags.deinit();

    try testing.expectEqual(0, diags.items.len);
    try testing.expect(!diags.hasErrors());
}

test "valid fragment" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\pub fn Page(allocator: zx.Allocator) zx.Component {
        \\    return (<><span>a</span><span>b</span></>);
        \\}
        \\const zx = @import("zx");
    ;

    var parse_result = try Parser.parse(allocator, source, .zx);
    defer parse_result.deinit(allocator);

    var diags = try check.validate(allocator, &parse_result);
    defer diags.deinit();

    try testing.expectEqual(0, diags.items.len);
    try testing.expect(!diags.hasErrors());
}

test "valid expression block" {
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

    var diags = try check.validate(allocator, &parse_result);
    defer diags.deinit();

    try testing.expectEqual(0, diags.items.len);
}

test "unclosed tag" {
    const allocator = std.testing.allocator;

    // Missing closing </div>
    const source: [:0]const u8 =
        \\(<div>)
    ;

    var parse_result = try Parser.parse(allocator, source, .zx);
    defer parse_result.deinit(allocator);

    var diags = try check.validate(allocator, &parse_result);
    defer diags.deinit();

    try testing.expect(diags.hasErrors());
    try testing.expect(diags.items.len > 0);
    try testing.expectEqual(check.Severity.err, diags.items[0].severity);
}

test "mismatched tags" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\(<div></span>)
    ;

    var parse_result = try Parser.parse(allocator, source, .zx);
    defer parse_result.deinit(allocator);

    var diags = try check.validate(allocator, &parse_result);
    defer diags.deinit();

    try testing.expect(diags.hasErrors());
    try testing.expect(diags.items.len > 0);
}

test "diagnostic position" {
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

    var diags = try check.validate(allocator, &parse_result);
    defer diags.deinit();

    try testing.expect(diags.hasErrors());
    // Positions are 0-based.
    try testing.expect(diags.items[0].start_line >= 0);
    try testing.expect(diags.items[0].end_line >= diags.items[0].start_line);
}

test "diagnostic message" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\(<div>)
    ;

    var parse_result = try Parser.parse(allocator, source, .zx);
    defer parse_result.deinit(allocator);

    var diags = try check.validate(allocator, &parse_result);
    defer diags.deinit();

    try testing.expect(diags.items.len > 0);
    try testing.expect(diags.items[0].message.len > 0);
}

test "broken line scope" {
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

    var diags = try check.validate(allocator, &parse_result);
    defer diags.deinit();

    try testing.expect(diags.hasErrors());
    try testing.expect(diags.items.len > 0);

    const last_line: u32 = 4;
    try testing.expectEqual(@as(u32, 1), diags.items[0].start_line);
    try testing.expect(diags.items[0].end_line < last_line);
}

test "Ast.parse valid" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\pub fn Page(allocator: zx.Allocator) zx.Component {
        \\    return (<p>OK</p>);
        \\}
        \\const zx = @import("zx");
    ;

    var result = try lang.Ast.parse(allocator, source, .{});
    defer result.deinit(allocator);

    try testing.expect(!result.diagnostics.hasErrors());
    try testing.expectEqual(0, result.diagnostics.items.len);
}

test "Ast.parse invalid" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\(<div>)
    ;

    var result = try lang.Ast.parse(allocator, source, .{});
    defer result.deinit(allocator);

    try testing.expect(result.diagnostics.hasErrors());
    try testing.expect(result.diagnostics.items.len > 0);
}

test "Ast.fmt valid" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\pub fn Page(allocator: zx.Allocator) zx.Component {
        \\    return (<p>Hello</p>);
        \\}
        \\const zx = @import("zx");
    ;

    var result = try lang.Ast.fmt(allocator, source);
    defer result.deinit(allocator);

    try testing.expect(!result.diagnostics.hasErrors());
    try testing.expect(result.source != null);
}

test "Ast.fmt invalid" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\(<div>)
    ;

    var result = try lang.Ast.fmt(allocator, source);
    defer result.deinit(allocator);

    try testing.expect(result.source == null);
    try testing.expect(result.diagnostics.hasErrors());
    try testing.expect(result.diagnostics.items.len > 0);
}

test "hasErrors empty" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\pub fn Page(allocator: zx.Allocator) zx.Component {
        \\    return (<span>ok</span>);
        \\}
        \\const zx = @import("zx");
    ;

    var parse_result = try Parser.parse(allocator, source, .zx);
    defer parse_result.deinit(allocator);

    var diags = try check.validate(allocator, &parse_result);
    defer diags.deinit();

    try testing.expect(!diags.hasErrors());
}

fn validateSource(allocator: std.mem.Allocator, source: [:0]const u8) !check.DiagnosticList {
    var parse_result = try Parser.parse(allocator, source, .zx);
    defer parse_result.deinit(allocator);
    return check.validate(allocator, &parse_result);
}

fn countWithMessage(diags: check.DiagnosticList, needle: []const u8) usize {
    var n: usize = 0;
    for (diags.items) |d| {
        if (std.mem.indexOf(u8, d.message, needle) != null) n += 1;
    }
    return n;
}

fn hasMessage(diags: check.DiagnosticList, needle: []const u8) bool {
    return countWithMessage(diags, needle) > 0;
}

test "semantic: invalid html tag name" {
    const allocator = std.testing.allocator;
    var diags = try validateSource(allocator,
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<blah>hi</blah>);
        \\}
        \\const zx = @import("zx");
    );
    defer diags.deinit();

    try testing.expect(diags.hasErrors());
    try testing.expect(hasMessage(diags, "not a valid HTML element"));
}

test "semantic: known elements are valid" {
    const allocator = std.testing.allocator;
    var diags = try validateSource(allocator,
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<div><p>ok</p><span>x</span></div>);
        \\}
        \\const zx = @import("zx");
    );
    defer diags.deinit();

    try testing.expectEqual(@as(usize, 0), diags.items.len);
}

test "semantic: svg elements are valid" {
    const allocator = std.testing.allocator;
    var diags = try validateSource(allocator,
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<svg viewBox="0 0 10 10"><circle cx="5" cy="5" r="4" /><path d="M0 0h10" /><g><rect width="1" height="1" /></g></svg>);
        \\}
        \\const zx = @import("zx");
    );
    defer diags.deinit();

    try testing.expectEqual(@as(usize, 0), diags.items.len);
}

test "semantic: svg camelCase elements are valid" {
    const allocator = std.testing.allocator;
    var diags = try validateSource(allocator,
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<svg><clipPath id="c"><circle cx="0" cy="0" r="1" /></clipPath><linearGradient id="g"><stop offset="0" /></linearGradient></svg>);
        \\}
        \\const zx = @import("zx");
    );
    defer diags.deinit();

    try testing.expectEqual(@as(usize, 0), diags.items.len);
}

test "semantic: components are not html-validated" {
    const allocator = std.testing.allocator;
    var diags = try validateSource(allocator,
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<div><Foo /><ns.Bar /></div>);
        \\}
        \\const zx = @import("zx");
    );
    defer diags.deinit();

    try testing.expect(!diags.hasErrors());
    try testing.expect(!hasMessage(diags, "not a valid HTML element"));
}

test "semantic: custom-element and component classification" {
    // Hyphenated custom elements and namespaced/uppercase components are not
    // subject to HTML element-name validation. (Tested directly because the
    // ZX grammar does not yet parse hyphenated tag names inline.)
    try testing.expect(check.elements.isCustomOrComponent("my-widget"));
    try testing.expect(check.elements.isCustomOrComponent("Foo"));
    try testing.expect(check.elements.isCustomOrComponent("ns.Bar"));
    try testing.expect(check.elements.isCustomOrComponent("fragment"));
    try testing.expect(!check.elements.isCustomOrComponent("div"));
    try testing.expect(!check.elements.isCustomOrComponent("blah"));
}

test "semantic: fragment is not html-validated" {
    const allocator = std.testing.allocator;
    var diags = try validateSource(allocator,
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<fragment><p>a</p></fragment>);
        \\}
        \\const zx = @import("zx");
    );
    defer diags.deinit();

    try testing.expect(!diags.hasErrors());
}

test "semantic: deprecated element" {
    const allocator = std.testing.allocator;
    var diags = try validateSource(allocator,
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<center>old</center>);
        \\}
        \\const zx = @import("zx");
    );
    defer diags.deinit();

    try testing.expect(diags.hasErrors());
    try testing.expect(hasMessage(diags, "deprecated and unsupported"));
}

test "semantic: html element cannot self-close" {
    const allocator = std.testing.allocator;
    var diags = try validateSource(allocator,
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<div><span /></div>);
        \\}
        \\const zx = @import("zx");
    );
    defer diags.deinit();

    try testing.expect(diags.hasErrors());
    try testing.expect(hasMessage(diags, "can't self-close"));
}

test "semantic: void element self-close is allowed" {
    const allocator = std.testing.allocator;
    var diags = try validateSource(allocator,
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<div><br /><img src="x.png" /><hr /></div>);
        \\}
        \\const zx = @import("zx");
    );
    defer diags.deinit();

    try testing.expect(!diags.hasErrors());
    try testing.expect(!hasMessage(diags, "can't self-close"));
}

test "semantic: void element with end tag" {
    const allocator = std.testing.allocator;
    var diags = try validateSource(allocator,
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<div><br>x</br></div>);
        \\}
        \\const zx = @import("zx");
    );
    defer diags.deinit();

    try testing.expect(hasMessage(diags, "void elements have no end tag"));
}

test "semantic: duplicate attribute is a warning" {
    const allocator = std.testing.allocator;
    var diags = try validateSource(allocator,
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<div class="a" class="b">x</div>);
        \\}
        \\const zx = @import("zx");
    );
    defer diags.deinit();

    try testing.expect(hasMessage(diags, "duplicate attribute"));
    // Warnings must not block formatting/compilation.
    try testing.expect(!diags.hasErrors());
}

test "semantic: duplicate id is a warning" {
    const allocator = std.testing.allocator;
    var diags = try validateSource(allocator,
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<div id="x"><span id="x">y</span></div>);
        \\}
        \\const zx = @import("zx");
    );
    defer diags.deinit();

    try testing.expect(hasMessage(diags, "duplicate id"));
    try testing.expect(!diags.hasErrors());
}

test "semantic: distinct ids are fine" {
    const allocator = std.testing.allocator;
    var diags = try validateSource(allocator,
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<div id="x"><span id="y">z</span></div>);
        \\}
        \\const zx = @import("zx");
    );
    defer diags.deinit();

    try testing.expect(!hasMessage(diags, "duplicate id"));
}

test "semantic: unknown builtin attribute" {
    const allocator = std.testing.allocator;
    var diags = try validateSource(allocator,
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<div @notARealBuiltin={a}>x</div>);
        \\}
        \\const zx = @import("zx");
    );
    defer diags.deinit();

    try testing.expect(diags.hasErrors());
    try testing.expect(hasMessage(diags, "unknown ZX builtin attribute"));
}

test "semantic: known builtin attribute is fine" {
    const allocator = std.testing.allocator;
    var diags = try validateSource(allocator,
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<div @allocator={a} @rendering={.client}>x</div>);
        \\}
        \\const zx = @import("zx");
    );
    defer diags.deinit();

    try testing.expect(!hasMessage(diags, "unknown ZX builtin attribute"));
}

test "semantic: unknown builtin shorthand" {
    const allocator = std.testing.allocator;
    var diags = try validateSource(allocator,
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<div @{notARealBuiltin}>x</div>);
        \\}
        \\const zx = @import("zx");
    );
    defer diags.deinit();

    try testing.expect(diags.hasErrors());
    try testing.expect(hasMessage(diags, "unknown ZX builtin attribute"));
}

test "semantic: known builtin shorthand is fine" {
    const allocator = std.testing.allocator;
    var diags = try validateSource(allocator,
        \\pub fn Page(allocator: zx.Allocator) zx.Component {
        \\    return (<div @{allocator}>x</div>);
        \\}
        \\const zx = @import("zx");
    );
    defer diags.deinit();

    try testing.expect(!hasMessage(diags, "unknown ZX builtin attribute"));
}

test "semantic: skipped when syntax errors present" {
    const allocator = std.testing.allocator;
    // Unknown tag <blah> would normally be flagged, but the unclosed tag is a
    // syntax error, so the semantic pass is skipped to avoid cascading noise.
    var diags = try validateSource(allocator, "(<blah>)");
    defer diags.deinit();

    try testing.expect(diags.hasErrors());
    try testing.expect(!hasMessage(diags, "not a valid HTML element"));
}

const std = @import("std");
const testing = std.testing;
const zx = @import("zx");
const lang = @import("lang");
const Parser = lang.Parse;
const check = lang.Ast.check;
