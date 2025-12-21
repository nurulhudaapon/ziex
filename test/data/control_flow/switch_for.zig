pub fn Page(allocator: zx.Allocator) zx.Component {
    const user_type: UserType = .admin;
    const admin_users = [_][]const u8{ "John", "Jane" };
    const member_users = [_][]const u8{ "Jim", "Jill" };
    var _zx = zx.initWithAllocator(allocator);
    return _zx.zx(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                switch (user_type) {
                    .admin => blk_0: {
                        const __zx_children_0 = _zx.getAllocator().alloc(zx.Component, admin_users.len) catch unreachable;
                        for (admin_users, 0..) |name, _zx_i_0| {
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
                    },
                    .member => blk_1: {
                        const __zx_children_1 = _zx.getAllocator().alloc(zx.Component, member_users.len) catch unreachable;
                        for (member_users, 0..) |name, _zx_i_1| {
                            __zx_children_1[_zx_i_1] = _zx.zx(
                                .p,
                                .{
                                    .children = &.{
                                        _zx.txt(name),
                                    },
                                },
                            );
                        }
                        break :blk_1 _zx.zx(.fragment, .{ .children = __zx_children_1 });
                    },
                },
            },
        },
    );
}

const zx = @import("zx");

const UserType = enum { admin, member };
