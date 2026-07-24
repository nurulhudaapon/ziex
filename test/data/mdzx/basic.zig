pub fn _zx_md(ctx: *@import("zx").ComponentCtx(struct { children: @import("zx").Component })) @import("zx").Component {
    var _zx1 = @import("zx").x.allocInit(ctx.allocator, .{ .src = @src() });
    return _zx1.ele(
        .h1,
        .{
            .allocator = ctx.allocator,
            .children = &.{
                _zx1.txt("hi"),
            },
        },
    );
}
