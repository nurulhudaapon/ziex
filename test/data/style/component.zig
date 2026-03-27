const std = @import("std");
const zx = @import("zx");

pub fn Page(allocator: std.mem.Allocator) zx.Component {
    var ctx = zx.allocInit(allocator);
    const style = zx.style.styleInit(.{
        zx.style.color(.hex(0x0000ff)),
        zx.style.margin_top(.px(20)),
    });
    return ctx.ele(.div, .{
        .attributes = &.{ ctx.attr("style", style).? },
        .children = &.{ ctx.txt("Component style") },
    });
}
