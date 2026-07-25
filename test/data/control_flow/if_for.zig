pub fn Page(allocator: zx.Allocator) zx.Component {
    const show_users = true;
    const user_names = [_][]const u8{ "John", "Jane", "Jim", "Jill" };
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                if (show_users) _zx.ele(
                    .fragment,
                    .{
                        .children = _zx.chs(.{
                            (_zx_for_blk_0: {
                                const __zx_children_0 = _zx.getAlloc().alloc(@import("zx").Component, user_names.len) catch unreachable;
                                for (user_names, 0..) |name, _zx_i_0| {
                                    __zx_children_0[_zx_i_0] = _zx.ele(
                                        .p,
                                        .{
                                            .children = _zx.chs(.{
                                                _zx.expr(name),
                                            }),
                                        },
                                    );
                                }
                                break :_zx_for_blk_0 _zx.ele(.fragment, .{ .children = __zx_children_0 });
                            }),
                        }),
                    },
                ) else _zx.ele(
                    .p,
                    .{
                        .children = _zx.chs(.{
                            _zx.txt("Users hidden"),
                        }),
                    },
                ),
            }),
        },
    );
}

const zx = @import("zx");
