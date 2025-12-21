pub fn Page(allocator: zx.Allocator) zx.Component {
    const hello_child = _zx.ele(
        .div,
        .{
            .children = &.{
                _zx.txt("Hello!"),
            },
        },
    );
    var _zx = zx.allocInit(allocator);
    return _zx.ele(
        .section,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.cmp(ChildComponent, .{ .children = hello_child }),
                _zx.cmp(ChildComponent, .{ .children = _zx.ele(
                    .div,
                    .{
                        .children = &.{
                            _zx.txt("Hello!"),
                        },
                    },
                ) }),
            },
        },
    );
}

const Props = struct { children: zx.Component };
pub fn ChildComponent(allocator: zx.Allocator, props: Props) zx.Component {
    var _zx = zx.allocInit(allocator);
    return _zx.ele(
        .div,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.expr(props.children),
            },
        },
    );
}

const zx = @import("zx");
