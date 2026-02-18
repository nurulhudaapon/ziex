pub fn _zx_md(ctx: *@import("zx").ComponentCtx(struct { children: @import("zx").Component })) @import("zx").Component {
    var _zx = @import("zx").allocInit(ctx.allocator);
    return _zx.ele(
        .h1,
        .{
            .allocator = ctx.allocator,
            .children = &.{
                _zx.txt("hi"),
            },
        },
    );
}
