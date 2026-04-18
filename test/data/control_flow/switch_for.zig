pub fn Page(allocator: zx.Allocator) zx.Component {
    const user_type: UserType = .admin;
    const admin_users = [_][]const u8{ "John", "Jane" };
    const member_users = [_][]const u8{ "Jim", "Jill" };
    var _zx = @import("zx").x.allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                switch (user_type) {
                    .admin => _zx_for_blk_0: {
                        const __zx_children_0 = _zx.getAlloc().alloc(@import("zx").Component, admin_users.len) catch unreachable;
                        for (admin_users, 0..) |name, _zx_i_0| {
                            __zx_children_0[_zx_i_0] = _zx.ele(
                                .p,
                                .{
                                    .children = &.{
                                        _zx.ele(
                                            .p,
                                            .{
                                                .children = &.{
                                                    _zx.ele(
                                                        .div,
                                                        .{
                                                            .children = &.{
                                                                _zx.expr(name),
                                                            },
                                                        },
                                                    ),
                                                },
                                            },
                                        ),
                                    },
                                },
                            );
                        }
                        break :_zx_for_blk_0 _zx.ele(.fragment, .{ .children = __zx_children_0 });
                    },
                    .member => _zx_for_blk_1: {
                        const __zx_children_1 = _zx.getAlloc().alloc(@import("zx").Component, member_users.len) catch unreachable;
                        for (member_users, 0..) |name, _zx_i_1| {
                            __zx_children_1[_zx_i_1] = _zx.ele(
                                .p,
                                .{
                                    .children = &.{
                                        _zx.ele(
                                            .div,
                                            .{
                                                .children = &.{
                                                    _zx.expr(name),
                                                },
                                            },
                                        ),
                                        _zx.expr(name),
                                    },
                                },
                            );
                        }
                        break :_zx_for_blk_1 _zx.ele(.fragment, .{ .children = __zx_children_1 });
                    },
                },
            },
        },
    );
}

const zx = @import("zx");

const UserType = enum { admin, member };
