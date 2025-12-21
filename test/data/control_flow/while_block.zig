pub fn Page(allocator: zx.Allocator) zx.Component {
    var i: usize = 0;

    var _zx = zx.initWithAllocator(allocator);
    return _zx.zx(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                blk_0: {
                    var __zx_list_0 = @import("std").ArrayList(zx.Component).empty;
                    while (i < 3) : (i += 1) {
                        __zx_list_0.append(_zx.getAllocator(), _zx.zx(
                            .div,
                            .{
                                .children = &.{
                                    _zx.zx(
                                        .p,
                                        .{
                                            .children = &.{
                                                _zx.fmt("{d}", .{i}),
                                            },
                                        },
                                    ),
                                },
                            },
                        )) catch unreachable;
                    }
                    break :blk_0 _zx.zx(.fragment, .{ .children = __zx_list_0.items });
                },
            },
        },
    );
}

const zx = @import("zx");
