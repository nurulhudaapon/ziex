pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx_for_blk_0: {
                    const __zx_children_0 = _zx.getAlloc().alloc(@import("zx").Component, 10 - 0) catch unreachable;
                    for (0..10, 0..) |n, _zx_i_0| {
                        __zx_children_0[_zx_i_0] = _zx.ele(
                            .span,
                            .{
                                .children = &.{
                                    _zx.expr(n),
                                },
                            },
                        );
                    }
                    break :_zx_for_blk_0 _zx.ele(.fragment, .{ .children = __zx_children_0 });
                },
            },
        },
    );
}

const zx = @import("zx");
const std = @import("std");
