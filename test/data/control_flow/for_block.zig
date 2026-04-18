pub fn Page(allocator: zx.Allocator) zx.Component {
    const chars = "ABC";
    var _zx = @import("zx").x.allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx_for_blk_0: {
                    const __zx_children_0 = _zx.getAlloc().alloc(@import("zx").Component, chars.len) catch unreachable;
                    for (chars, 0..) |char, _zx_i_0| {
                        __zx_children_0[_zx_i_0] = _zx.ele(
                            .div,
                            .{
                                .children = &.{
                                    _zx.ele(
                                        .i,
                                        .{
                                            .children = &.{
                                                _zx.expr(char),
                                            },
                                        },
                                    ),
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
