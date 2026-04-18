pub fn Page(allocator: zx.Allocator) zx.Component {
    const groups = [_]struct { name: []const u8, members: []const []const u8 }{
        .{ .name = "Team A", .members = &[_][]const u8{ "John", "Jane" } },
        .{ .name = "Team B", .members = &[_][]const u8{ "Jim", "Jill" } },
    };
    var _zx = @import("zx").x.allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx_for_blk_0: {
                    const __zx_children_0 = _zx.getAlloc().alloc(@import("zx").Component, groups.len) catch unreachable;
                    for (groups, 0..) |group, _zx_i_0| {
                        __zx_children_0[_zx_i_0] = _zx.ele(
                            .div,
                            .{
                                .children = &.{
                                    _zx_for_blk_1: {
                                        const __zx_children_1 = _zx.getAlloc().alloc(@import("zx").Component, group.members.len) catch unreachable;
                                        for (group.members, 0..) |member, _zx_i_1| {
                                            __zx_children_1[_zx_i_1] = _zx.ele(
                                                .p,
                                                .{
                                                    .children = &.{
                                                        _zx.expr(member),
                                                    },
                                                },
                                            );
                                        }
                                        break :_zx_for_blk_1 _zx.ele(.fragment, .{ .children = __zx_children_1 });
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
