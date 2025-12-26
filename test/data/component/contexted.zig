pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = zx.allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.cmp(Wrapper, .{ .children = _zx.ele(.fragment, .{ .children = &.{
                    _zx.ele(
                        .p,
                        .{
                            .children = &.{
                                _zx.txt("Wrapped content"),
                            },
                        },
                    ),
                } }) }),
                _zx.cmp(Card, .{ .children = _zx.ele(.fragment, .{ .children = &.{
                    _zx.ele(
                        .span,
                        .{
                            .children = &.{
                                _zx.txt("Card content"),
                            },
                        },
                    ),
                } }) }),
            },
        },
    );
}

/// Component using ComponentContext (void props, children only)
pub fn Wrapper(ctx: *zx.ComponentContext) zx.Component {
    var _zx = zx.allocInit(ctx.allocator);
    return _zx.ele(
        .div,
        .{
            .allocator = ctx.allocator,
            .attributes = _zx.attrs(.{
                _zx.attr("class", "wrapper"),
            }),
            .children = &.{
                _zx.expr(ctx.children),
            },
        },
    );
}

/// Another component using ComponentContext
fn Card(ctx: *zx.ComponentContext) zx.Component {
    var _zx = zx.allocInit(ctx.allocator);
    return _zx.ele(
        .article,
        .{
            .allocator = ctx.allocator,
            .attributes = _zx.attrs(.{
                _zx.attr("class", "card"),
            }),
            .children = &.{
                _zx.expr(ctx.children),
            },
        },
    );
}

const zx = @import("zx");
