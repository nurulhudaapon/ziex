pub fn Page(allocator: zx.Allocator) zx.Component {
    const users = [_]struct { name: []const u8, is_active: bool }{
        .{ .name = "John", .is_active = true },
        .{ .name = "Jane", .is_active = false },
        .{ .name = "Jim", .is_active = true },
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
                            .fragment,
                            .{
                                .children = &.{
                                    (if (user.is_active) _zx.ele(
                                        .p,
                                        .{
                                            .children = &.{
                                                _zx.expr(user.name),
                                                _zx.txt(" (Active)"),
                                            },
                                        },
                                    ) else _zx.ele(
                                        .p,
                                        .{
                                            .children = &.{
                                                _zx.expr(user.name),
                                                _zx.txt(" (Inactive)"),
                                            },
                                        },
                                    )),
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
