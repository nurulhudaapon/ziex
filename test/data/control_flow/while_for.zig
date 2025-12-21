pub fn Page(allocator: zx.Allocator) zx.Component {
    var i: usize = 0;
    const items = [_][]const u8{ "a", "b" };

    var _zx = zx.initWithAllocator(allocator);
    return _zx.zx(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                blk_0: {
                    var __zx_list_0 = @import("std").ArrayList(zx.Component).empty;
                    while (i < 2) : (i += 1) {
                        __zx_list_0.append(_zx.getAllocator(), _zx.zx(
                            .div,
                            .{
                                .children = &.{
                                    blk_1: {
                                        const __zx_children_1 = _zx.getAllocator().alloc(zx.Component, items.len) catch unreachable;
                                        for (items, 0..) |item, _zx_i_1| {
                                            __zx_children_1[_zx_i_1] = _zx.zx(
                                                .p,
                                                .{
                                                    .children = &.{
                                                        _zx.txt(item),
                                                    },
                                                },
                                            );
                                        }
                                        break :blk_1 _zx.zx(.fragment, .{ .children = __zx_children_1 });
                                    },
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
