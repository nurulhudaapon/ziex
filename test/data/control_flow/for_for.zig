pub fn Page(allocator: zx.Allocator) zx.Component {
    const groups = [_]struct { name: []const u8, members: []const []const u8 }{
        .{ .name = "Team A", .members = &[_][]const u8{ "John", "Jane" } },
        .{ .name = "Team B", .members = &[_][]const u8{ "Jim", "Jill" } },
    };
    var _zx = zx.initWithAllocator(allocator);
    return _zx.zx(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                blk_0: {
                    const __zx_children_0 = _zx.getAllocator().alloc(zx.Component, groups.len) catch unreachable;
                    for (groups, 0..) |group, _zx_i_0| {
                        __zx_children_0[_zx_i_0] = _zx.zx(
                            .div,
                            .{
                                .children = &.{
                                    blk_1: {
                                        const __zx_children_1 = _zx.getAllocator().alloc(zx.Component, group.members.len) catch unreachable;
                                        for (group.members, 0..) |member, _zx_i_1| {
                                            __zx_children_1[_zx_i_1] = _zx.zx(
                                                .p,
                                                .{
                                                    .children = &.{
                                                        _zx.txt(member),
                                                    },
                                                },
                                            );
                                        }
                                        break :blk_1 _zx.zx(.fragment, .{ .children = __zx_children_1 });
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
