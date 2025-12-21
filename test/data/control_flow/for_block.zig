pub fn Page(allocator: zx.Allocator) zx.Component {
    const chars = "ABC";
    var _zx = zx.initWithAllocator(allocator);
    return _zx.zx(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                blk_0: {
                    const __zx_children_0 = _zx.getAllocator().alloc(zx.Component, chars.len) catch unreachable;
                    for (chars, 0..) |char, _zx_i_0| {
                        __zx_children_0[_zx_i_0] = _zx.zx(
                            .div,
                            .{
                                .children = &.{
                                    _zx.zx(
                                        .i,
                                        .{
                                            .children = &.{
                                                _zx.fmt("{c}", .{char}),
                                            },
                                        },
                                    ),
                                },
                            },
                        );
                    }
                    break :blk_0 _zx.zx(.fragment, .{ .children = __zx_children_0 });
                },
            },
        },
    );
}

const zx = @import("zx");
