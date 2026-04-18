pub fn Page(allocator: zx.Allocator) zx.Component {
    const groups = [_][]const u8{ "A", "B" };
    var j: usize = 0;

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
                                    _zx_whl_blk_1: {
                                        var __zx_list_1 = @import("std").ArrayList(@import("zx").Component).empty;
                                        while (j < 2) : (j += 1) {
                                            __zx_list_1.append(_zx.getAlloc(), _zx.ele(
                                                .p,
                                                .{
                                                    .children = &.{
                                                        _zx.expr(j),
                                                        _zx.txt(" : "),
                                                        _zx.expr(group),
                                                    },
                                                },
                                            )) catch unreachable;
                                        }
                                        break :_zx_whl_blk_1 _zx.ele(.fragment, .{ .children = __zx_list_1.items });
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
