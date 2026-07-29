const std = @import("std");
const testing = std.testing;
const html_hover = @import("html_hover");

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
