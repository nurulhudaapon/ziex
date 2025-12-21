pub fn Page(allocator: zx.Allocator) zx.Component {
    const users = [_]struct { name: []const u8, role: UserRole }{
        .{ .name = "John", .role = .admin },
        .{ .name = "Jane", .role = .member },
        .{ .name = "Jim", .role = .guest },
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
                            .div,
                            .{
                                .children = &.{
                                    _zx.zx(
                                        .p,
                                        .{
                                            .children = &.{
                                                _zx.txt(user.name),
                                            },
                                        },
                                    ),
                                    switch (user.role) {
                                        .admin => _zx.zx(
                                            .span,
                                            .{
                                                .children = &.{
                                                    _zx.txt("Admin"),
                                                },
                                            },
                                        ),
                                        .member => _zx.zx(
                                            .span,
                                            .{
                                                .children = &.{
                                                    _zx.txt("Member"),
                                                },
                                            },
                                        ),
                                        .guest => _zx.zx(
                                            .span,
                                            .{
                                                .children = &.{
                                                    _zx.txt("Guest"),
                                                },
                                            },
                                        ),
                                    },
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

const UserRole = enum { admin, member, guest };
