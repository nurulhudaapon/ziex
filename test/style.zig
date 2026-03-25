const std = @import("std");
const zx = @import("zx");

test "Style formatting" {
    const allocator = std.testing.allocator;
    const style: zx.Style = .{
        .display = .flex,
        .flex_direction = .column,
        .background_color = .hex(0xff0000),
        .padding_top = .px(10),
        .width = .px(100),
    };

    const result = try std.fmt.allocPrint(allocator, "{f}", .{style});
    defer allocator.free(result);

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

    const style: zx.Style = .{
        .color = .hex(0x0000ff),
        .margin_top = .px(20),
    };

    const comp = ctx.ele(.div, .{
        .attributes = &[_]zx.Element.Attribute{
            ctx.attr("style", style).?,
            ctx.attr("class", "my-div").?,
        },
        .children = &[_]zx.Component{
            ctx.txt("Hello with style"),
        },
    });
    // deinit is not strictly needed with arena but good practice if we want to test it
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
    const style: zx.Style = .{
        .background_color = .hex(0x0000ff),
        .hover = &.{
            .background_color = .hex(0xff0000),
        },
    };

    try std.testing.expect(style.hover != null);
    try std.testing.expectEqual(zx.style.generated.BackgroundColor.hex(0xff0000), style.hover.?.background_color);
}

test "Style shorthands" {
    const allocator = std.testing.allocator;
    const style: zx.Style = .{
        .padding = .px2(10, 20),
        .margin = .px4(5, 10, 15, 20),
    };

    const result = try std.fmt.allocPrint(allocator, "{f}", .{style});
    defer allocator.free(result);
    
    try std.testing.expect(std.mem.indexOf(u8, result, "padding: 10px 20px;") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "margin: 5px 10px 15px 20px;") != null);
}
