const std = @import("std");
const zx = @import("zx");

pub fn Page(allocator: std.mem.Allocator) zx.Component {
    var ctx = zx.allocInit(allocator);
    const style = zx.style.styleInit(.{
        zx.style.display(.flex),
        zx.style.flex_direction(.column),
    });
    return ctx.ele(.div, .{
        .attributes = &.{ ctx.attr("style", style).? },
        .children = &.{ ctx.txt("Basic style") },
    });
}
