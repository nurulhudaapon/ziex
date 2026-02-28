pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.cmp(
                    Wrapper,
                    "Wrapper",
                    .{},
                    .{ .children = _zx.ele(.fragment, .{ .children = &.{
                        _zx.ele(
                            .p,
                            .{
                                .children = &.{
                                    _zx.txt("Wrapped content"),
                                },
                            },
                        ),
                    } }) },
                ),
                _zx.cmp(
                    Container,
                    "Container",
                    .{},
                    .{ .children = _zx.ele(.fragment, .{ .children = &.{
                        _zx.ele(
                            .span,
                            .{
                                .children = &.{
                                    _zx.txt("First"),
                                },
                            },
                        ),
                        _zx.ele(
                            .span,
                            .{
                                .children = &.{
                                    _zx.txt("Second"),
                                },
                            },
                        ),
                    } }) },
                ),
            },
        },
    );
}

const WrapperProps = struct { children: zx.Component };
fn Wrapper(allocator: zx.Allocator, props: WrapperProps) zx.Component {
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .div,
        .{
            .allocator = allocator,
            .attributes = _zx.attrs(.{
                _zx.attr("class", "wrapper"),
            }),
            .children = &.{
                _zx.expr(props.children),
            },
        },
    );
}

const ContainerProps = struct { children: zx.Component };
fn Container(allocator: zx.Allocator, props: ContainerProps) zx.Component {
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .section,
        .{
            .allocator = allocator,
            .attributes = _zx.attrs(.{
                _zx.attr("class", "container"),
            }),
            .children = &.{
                _zx.expr(props.children),
            },
        },
    );
}

const zx = @import("zx");
