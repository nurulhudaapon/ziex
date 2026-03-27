const std = @import("std");
const zx = @import("zx");

pub fn Page(allocator: std.mem.Allocator) zx.Component {
    var ctx = zx.allocInit(allocator);
    const s = zx.style;
    return ctx.ele(.div, .{
        .attributes = &.{
            ctx.attr("style", s.styleInit(.{ s.display(.flex), s.row_gap(.px(10)) })).?,
        },
        .children = &.{
            ctx.ele(.span, .{ .children = &.{ ctx.txt("Item 1") } }),
            ctx.ele(.span, .{ .children = &.{ ctx.txt("Item 2") } }),
        },
    });
}
