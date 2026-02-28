pub fn Page(allocator: zx.Allocator) zx.Component {
    const hello_child = _zx_ele_blk_0: {
        var _zx = @import("zx").allocInit(allocator);
        break :_zx_ele_blk_0 _zx.ele(
            .div,
            .{
                .allocator = allocator,
                .children = &.{
                    _zx.txt("Hello!"),
                },
            },
        );
    };
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .section,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.cmp(
                    ChildComponent,
                    .{ .name = "ChildComponent" },
                    .{ .children = hello_child },
                ),
                _zx.cmp(
                    ChildComponent,
                    .{ .name = "ChildComponent" },
                    .{ .children = _zx.ele(
                        .div,
                        .{
                            .children = &.{
                                _zx.txt("Hello!"),
                            },
                        },
                    ) },
                ),
            },
        },
    );
}

// Note: Not providing allocator here will use the default allocator (std.heap.page_allocator) and will have performance penalty
// Only use this when you need to create a component that doesn't need to allocate memory, like a complete static element.
const hello_child_outside = _zx_ele_blk_1: {
    var _zx = @import("zx").init();
    break :_zx_ele_blk_1 _zx.ele(
        .div,
        .{
            .children = &.{
                _zx.txt("Hello!"),
            },
        },
    );
};

const Props = struct { children: zx.Component };
pub fn ChildComponent(allocator: zx.Allocator, props: Props) zx.Component {
    var _zx = @import("zx").allocInit(allocator);
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
const std = @import("std");
