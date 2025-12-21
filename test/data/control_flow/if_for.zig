pub fn Page(allocator: zx.Allocator) zx.Component {
    const show_users = true;
    const user_names = [_][]const u8{ "John", "Jane", "Jim", "Jill" };
    var _zx = zx.initWithAllocator(allocator);
    return _zx.zx(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                if (show_users) _zx.zx(
                    .fragment,
                    .{
                        .children = &.{
                            (blk_0: {
                                const __zx_children_0 = _zx.getAllocator().alloc(zx.Component, user_names.len) catch unreachable;
                                for (user_names, 0..) |name, _zx_i_0| {
                                    __zx_children_0[_zx_i_0] = _zx.zx(
                                        .p,
                                        .{
                                            .children = &.{
                                                _zx.txt(name),
                                            },
                                        },
                                    );
                                }
                                break :blk_0 _zx.zx(.fragment, .{ .children = __zx_children_0 });
                            }),
                        },
                    },
                ) else _zx.zx(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Users hidden"),
                        },
                    },
                ),
            },
        },
    );
}

const zx = @import("zx");
