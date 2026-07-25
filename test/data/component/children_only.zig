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
                    Container,
                    .{ .src = @src() },
                    .{ .name = "Container" },
                    .{ .children = _zx.ele(.fragment, .{ .children = _zx.chs(.{
                        _zx.ele(
                            .span,
                            .{
                                .children = _zx.chs(.{
                                    _zx.txt("First"),
                                }),
                            },
                        ),
                        _zx.ele(
                            .span,
                            .{
                                .children = _zx.chs(.{
                                    _zx.txt("Second"),
                                }),
                            },
                        ),
                    }) }) },
                ),
            }),
        },
    );
}

const WrapperProps = struct { children: zx.Component };
fn Wrapper(allocator: zx.Allocator, props: WrapperProps) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .div,
        .{
            .allocator = allocator,
            .attributes = _zx.attrs(.{
                _zx.attr(@src(), "class", "wrapper"),
            }),
            .children = _zx.chs(.{
                _zx.expr(props.children),
            }),
        },
    );
}

const ContainerProps = struct { children: zx.Component };
fn Container(allocator: zx.Allocator, props: ContainerProps) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .section,
        .{
            .allocator = allocator,
            .attributes = _zx.attrs(.{
                _zx.attr(@src(), "class", "container"),
            }),
            .children = _zx.chs(.{
                _zx.expr(props.children),
            }),
        },
    );
}

const zx = @import("zx");
