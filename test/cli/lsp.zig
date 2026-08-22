const std = @import("std");
const testing = std.testing;
const html = @import("html_hover");
const html_hover = html.hover;
const html_complete = html.complete;

fn offsetOf(src: []const u8, needle: []const u8, into: u32) u32 {
    const idx = std.mem.indexOf(u8, src, needle).?;
    return @intCast(idx + into);
}

test "hover > element tag name" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<div class="x">hi</div>);
        \\}
    ;
    // Point at the "div" in the start tag.
    const off = offsetOf(src, "<div", 1);
    const md = (try html_hover.hoverMarkdown(arena, src, off)) orelse return error.NoHover;
    try testing.expect(std.mem.indexOf(u8, md, "<div>") != null);
    try testing.expect(std.mem.indexOf(u8, md, "no special meaning") != null);
    try testing.expect(std.mem.indexOf(u8, md, "MDN Reference") != null);
}

test "hover > global attribute name" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<div class="x">hi</div>);
        \\}
    ;
    const off = offsetOf(src, "class=", 1);
    const md = (try html_hover.hoverMarkdown(arena, src, off)) orelse return error.NoHover;
    try testing.expect(std.mem.indexOf(u8, md, "class") != null);
    try testing.expect(std.mem.indexOf(u8, md, "space-separated list of the classes") != null);
}

test "hover > element-specific attribute name" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<a href="/x">link</a>);
        \\}
    ;
    const off = offsetOf(src, "href=", 1);
    const md = (try html_hover.hoverMarkdown(arena, src, off)) orelse return error.NoHover;
    try testing.expect(std.mem.indexOf(u8, md, "href") != null);
    try testing.expect(std.mem.indexOf(u8, md, "hyperlink points to") != null);
    // The enclosing tag should be reflected.
    try testing.expect(std.mem.indexOf(u8, md, "<a>") != null);
}

test "hover > unknown element returns null" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<Foo />);
        \\}
    ;
    const off = offsetOf(src, "<Foo", 1);
    try testing.expect((try html_hover.hoverMarkdown(arena, src, off)) == null);
}

test "hover > cursor outside tag returns null" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<div>hi</div>);
        \\}
    ;
    const off = offsetOf(src, "Page", 1);
    try testing.expect((try html_hover.hoverMarkdown(arena, src, off)) == null);
}

test "hover > void element self-closing tag" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<div><br /></div>);
        \\}
    ;
    const off = offsetOf(src, "<br", 1);
    const md = (try html_hover.hoverMarkdown(arena, src, off)) orelse return error.NoHover;
    try testing.expect(std.mem.indexOf(u8, md, "<br>") != null);
}

test "hover > builtin attribute @allocator" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<div @allocator={a}>hi</div>);
        \\}
    ;
    const off = offsetOf(src, "@allocator", 1);
    const md = (try html_hover.hoverMarkdown(arena, src, off)) orelse return error.NoHover;
    try testing.expect(std.mem.indexOf(u8, md, "@allocator") != null);
    try testing.expect(std.mem.indexOf(u8, md, "builtin") != null);
}

test "hover > builtin shorthand @{allocator}" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(allocator: zx.Allocator) zx.Component {
        \\    return (<div @{allocator}>hi</div>);
        \\}
    ;
    const off = offsetOf(src, "@{allocator}", 2);
    const md = (try html_hover.hoverMarkdown(arena, src, off)) orelse return error.NoHover;
    try testing.expect(std.mem.indexOf(u8, md, "@allocator") != null);
}

test "hover > attribute shorthand {class}" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<div {class}>hi</div>);
        \\}
    ;
    const off = offsetOf(src, "{class}", 1);
    const md = (try html_hover.hoverMarkdown(arena, src, off)) orelse return error.NoHover;
    try testing.expect(std.mem.indexOf(u8, md, "class") != null);
}

test "completion > tag name after <" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<di
    ;
    const off: u32 = @intCast(src.len);
    const result = (try html_complete.complete(arena, src, off)) orelse return error.NoCompletion;
    const items = switch (result) {
        .completion_list => |list| list.items,
        .completion_items => |items| items,
    };
    var found_div = false;
    for (items) |item| {
        if (std.mem.eql(u8, item.label, "div")) found_div = true;
    }
    try testing.expect(found_div);
}

test "completion > builtin attribute after @" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<div @
    ;
    const off: u32 = @intCast(src.len);
    const result = (try html_complete.complete(arena, src, off)) orelse return error.NoCompletion;
    const items = switch (result) {
        .completion_list => |list| list.items,
        .completion_items => |items| items,
    };
    var found_allocator = false;
    for (items) |item| {
        if (std.mem.eql(u8, item.label, "@allocator")) found_allocator = true;
    }
    try testing.expect(found_allocator);
}

test "completion > outside zx block returns null" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    const x = a < b;
    ;
    const off = offsetOf(src, "a < b", 2);
    try testing.expect((try html_complete.complete(arena, src, off)) == null);
}

test "completion > tag snippet wraps with end tag" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<di
    ;
    const off: u32 = @intCast(src.len);
    const result = (try html_complete.complete(arena, src, off)) orelse return error.NoCompletion;
    const items = switch (result) {
        .completion_list => |list| list.items,
        .completion_items => |items| items,
    };
    var found = false;
    for (items) |item| {
        if (!std.mem.eql(u8, item.label, "div")) continue;
        try testing.expect(item.insertTextFormat == .Snippet);
        try testing.expectEqualStrings("div>$0</div>", item.insertText.?);
        found = true;
    }
    try testing.expect(found);
}

test "completion > void tag completes without end tag" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<br
    ;
    const off: u32 = @intCast(src.len);
    const result = (try html_complete.complete(arena, src, off)) orelse return error.NoCompletion;
    const items = switch (result) {
        .completion_list => |list| list.items,
        .completion_items => |items| items,
    };
    var found = false;
    for (items) |item| {
        if (!std.mem.eql(u8, item.label, "br")) continue;
        try testing.expectEqualStrings("br />", item.insertText.?);
        found = true;
    }
    try testing.expect(found);
}

test "hover > custom component does not use HTML element docs" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<Button>hi</Button>);
        \\}
    ;
    const off = offsetOf(src, "<Button", 1);
    try testing.expect((try html_hover.hoverMarkdown(arena, src, off)) == null);
}

test "completion > custom component does not suggest HTML attributes" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<Button 
    ;
    const off: u32 = @intCast(src.len);
    const result = try html_complete.complete(arena, src, off);
    if (result) |r| {
        const items = switch (r) {
            .completion_list => |list| list.items,
            .completion_items => |items| items,
        };
        for (items) |item| {
            // Builtins (@…) are fine; plain HTML attrs are not.
            try testing.expect(item.label.len > 0 and item.label[0] == '@');
        }
    }
}

test "hover > lowercase button still shows HTML docs" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<button>hi</button>);
        \\}
    ;
    const off = offsetOf(src, "<button", 1);
    const md = (try html_hover.hoverMarkdown(arena, src, off)) orelse return error.NoHover;
    try testing.expect(std.mem.indexOf(u8, md, "<button>") != null);
}

fn completionLabels(arena: std.mem.Allocator, src: []const u8, offset: u32) ![]const []const u8 {
    const result = (try html_complete.complete(arena, src, offset)) orelse return &.{};
    const items = switch (result) {
        .completion_list => |list| list.items,
        .completion_items => |items| items,
    };
    const labels = try arena.alloc([]const u8, items.len);
    for (items, 0..) |item, i| labels[i] = item.label;
    return labels;
}

fn hasLabel(labels: []const []const u8, want: []const u8) bool {
    for (labels) |label| {
        if (std.mem.eql(u8, label, want)) return true;
    }
    return false;
}

test "completion > tag name after element text" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<p @allocator={a}>hello <b
    ;
    const labels = try completionLabels(arena, src, @intCast(src.len));
    try testing.expect(hasLabel(labels, "b"));
    try testing.expect(hasLabel(labels, "br"));
}

test "completion > tag name after expression block" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<p @allocator={a}>{name} <str
    ;
    const labels = try completionLabels(arena, src, @intCast(src.len));
    try testing.expect(hasLabel(labels, "strong"));
}

test "completion > bare < after element text" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<p @allocator={a}>hello <
    ;
    const labels = try completionLabels(arena, src, @intCast(src.len));
    try testing.expect(hasLabel(labels, "span"));
}

test "completion > attribute after element text" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<p @allocator={a}>hello <a hr
    ;
    const labels = try completionLabels(arena, src, @intCast(src.len));
    try testing.expect(hasLabel(labels, "href"));
    try testing.expect(hasLabel(labels, "hreflang"));
}

test "completion > builtin attribute after element text" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<p @allocator={a}>hello <Counter @rend
    ;
    const labels = try completionLabels(arena, src, @intCast(src.len));
    try testing.expect(hasLabel(labels, "@rendering"));
}

test "completion > closing tag after element text" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<p @allocator={a}>hello </
    ;
    const labels = try completionLabels(arena, src, @intCast(src.len));
    try testing.expect(hasLabel(labels, "p"));
}

test "completion > zig less-than after markup stays null" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // A `<` used as a comparison must not be mistaken for a tag, even in a file
    // that also contains ZX markup.
    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<p @allocator={a}>hi</p>);
        \\}
        \\
        \\fn lt(x: usize, y: usize) bool {
        \\    return x <y
    ;
    try testing.expect((try html_complete.complete(arena, src, @intCast(src.len))) == null);
}

test "completion > zig less-than inside expression block stays null" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<p @allocator={a}>{if (x <y
    ;
    try testing.expect((try html_complete.complete(arena, src, @intCast(src.len))) == null);
}
