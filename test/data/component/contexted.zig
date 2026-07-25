pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                _zx.cmp(
                    Wrapper,
                    .{ .src = @src() },
                    .{ .name = "Wrapper" },
                    .{ .children = _zx.ele(.fragment, .{ .children = _zx.chs(.{
                        _zx.ele(
                            .p,
                            .{
                                .children = _zx.chs(.{
                                    _zx.txt("Wrapped content"),
                                }),
                            },
                        ),
                    }) }) },
                ),
                _zx.cmp(
                    Card,
                    .{ .src = @src() },
                    .{ .name = "Card" },
                    .{ .children = _zx.ele(.fragment, .{ .children = _zx.chs(.{
                        _zx.ele(
                            .span,
                            .{
                                .children = _zx.chs(.{
                                    _zx.txt("Card content"),
                                }),
                            },
                        ),
                    }) }) },
                ),
            }),
        },
    );
}

/// Component using ComponentContext (void props, children only)
pub fn Wrapper(ctx: *zx.ComponentContext) zx.Component {
    var _zx = @import("zx").x.allocInit(ctx.allocator, .{ .src = @src() });
    return _zx.ele(
        .div,
        .{
            .allocator = ctx.allocator,
            .attributes = _zx.attrs(.{
                _zx.attr(@src(), "class", "wrapper"),
            }),
            .children = _zx.chs(.{
                _zx.expr(ctx.children),
            }),
        },
    );
}

/// Another component using ComponentContext
fn Card(ctx: *zx.ComponentContext) zx.Component {
    var _zx = @import("zx").x.allocInit(ctx.allocator, .{ .src = @src() });
    return _zx.ele(
        .article,
        .{
            .allocator = ctx.allocator,
            .attributes = _zx.attrs(.{
                _zx.attr(@src(), "class", "card"),
            }),
            .children = _zx.chs(.{
                _zx.expr(ctx.children),
            }),
        },
    );
}

const zx = @import("zx");
