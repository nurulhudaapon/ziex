pub fn Page(allocator: zx.Allocator) zx.Component {
    const users = [_]struct { name: []const u8, is_active: bool }{
        .{ .name = "John", .is_active = true },
        .{ .name = "Jane", .is_active = false },
        .{ .name = "Jim", .is_active = true },
    };
    var _zx = zx.initWithAllocator(allocator);
    return _zx.zx(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                blk_0: {
                    const __zx_children_0 = _zx.getAllocator().alloc(zx.Component, users.len) catch unreachable;
                    for (users, 0..) |user, _zx_i_0| {
                        __zx_children_0[_zx_i_0] = _zx.zx(
                            .fragment,
                            .{
                                .children = &.{
                                    (if (user.is_active) _zx.zx(
                                        .p,
                                        .{
                                            .children = &.{
                                                _zx.txt(user.name),
                                                _zx.txt(" (Active)"),
                                            },
                                        },
                                    ) else _zx.zx(
                                        .p,
                                        .{
                                            .children = &.{
                                                _zx.txt(user.name),
                                                _zx.txt(" (Inactive)"),
                                            },
                                        },
                                    )),
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
