pub fn Page(allocator: zx.Allocator) zx.Component {
    const users = [_]struct { name: []const u8, role: UserRole }{
        .{ .name = "John", .role = .admin },
        .{ .name = "Jane", .role = .member },
        .{ .name = "Jim", .role = .guest },
    };
    var _zx = @import("zx").x.allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx_for_blk_0: {
                    const __zx_children_0 = _zx.getAlloc().alloc(@import("zx").Component, users.len) catch unreachable;
                    for (users, 0..) |user, _zx_i_0| {
                        __zx_children_0[_zx_i_0] = _zx.ele(
                            .div,
                            .{
                                .children = &.{
                                    _zx.ele(
                                        .p,
                                        .{
                                            .children = &.{
                                                _zx.expr(user.name),
                                            },
                                        },
                                    ),
                                    switch (user.role) {
                                        .admin => _zx.ele(
                                            .span,
                                            .{
                                                .children = &.{
                                                    _zx.txt("Admin"),
                                                },
                                            },
                                        ),
                                        .member => _zx.ele(
                                            .span,
                                            .{
                                                .children = &.{
                                                    _zx.txt("Member"),
                                                },
                                            },
                                        ),
                                        .guest => _zx.ele(
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
                    break :_zx_for_blk_0 _zx.ele(.fragment, .{ .children = __zx_children_0 });
                },
            },
        },
    );
}

const zx = @import("zx");

const UserRole = enum { admin, member, guest };
