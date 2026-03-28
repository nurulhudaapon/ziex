const std = @import("std");
const zx = @import("zx");

test "Style formatting" {
    const style = zx.style.init(&.{});

    const result = style.css;

    std.debug.print("\nGenerated CSS: {s}\n", .{result});

    try std.testing.expect(std.mem.indexOf(u8, result, "display: flex;") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "flex-direction: column;") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "background-color: #ff0000;") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "padding-top: 10px;") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "width: 100px;") != null);
}

test "Style in Component" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var ctx = zx.allocInit(arena_allocator);

    const style = zx.style.init(&.{
        .color(.hex(0x0000ff)),
        .margin_top(.px(20)),
    });

    const comp = ctx.ele(.div, .{
        .attributes = &[_]zx.Element.Attribute{
            ctx.attr("style", style).?,
            ctx.attr("class", "my-div").?,
        },
        .children = &[_]zx.Component{
            ctx.txt("Hello with style"),
        },
    });
    defer comp.deinit(arena_allocator);

    try std.testing.expectEqual(zx.ElementTag.div, comp.element.tag);

    var found_style = false;
    for (comp.element.attributes.?) |attr| {
        if (std.mem.eql(u8, attr.name, "style")) {
            const expected_style = "color: #0000ff; margin-top: 20px; ";
            try std.testing.expectEqualStrings(expected_style, attr.value.?);
            found_style = true;
        }
    }
    try std.testing.expect(found_style);
}

test "Style pseudo-states" {
    const style = zx.style.init(&.{
        .background_color(.hex(0x0000ff)),
        .hover(&zx.style.init(&.{
            .background_color(.hex(0xff0000)),
        })),
    });

    try std.testing.expect(std.mem.indexOf(u8, style.css, "background-color: #0000ff;") != null);
}

test "Style shorthands" {
    const style = zx.style.init(&.{
        .padding(.px2(10, 20)),
        .margin(.px4(5, 10, 15, 20)),
    });

    const result = style.css;

    try std.testing.expect(std.mem.indexOf(u8, result, "padding: 10px 20px;") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "margin: 5px 10px 15px 20px;") != null);
}
