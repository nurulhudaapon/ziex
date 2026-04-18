pub fn Page(allocator: zx.Allocator) zx.Component {
    var i: usize = 0;
    const items = [_][]const u8{ "a", "b" };

    var _zx = @import("zx").x.allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx_whl_blk_0: {
                    var __zx_list_0 = @import("std").ArrayList(@import("zx").Component).empty;
                    while (i < 2) : (i += 1) {
                        __zx_list_0.append(_zx.getAlloc(), _zx.ele(
                            .div,
                            .{
                                .children = &.{
                                    _zx_for_blk_1: {
                                        const __zx_children_1 = _zx.getAlloc().alloc(@import("zx").Component, items.len) catch unreachable;
                                        for (items, 0..) |item, _zx_i_1| {
                                            __zx_children_1[_zx_i_1] = _zx.ele(
                                                .p,
                                                .{
                                                    .children = &.{
                                                        _zx.expr(item),
                                                    },
                                                },
                                            );
                                        }
                                        break :_zx_for_blk_1 _zx.ele(.fragment, .{ .children = __zx_children_1 });
                                    },
                                },
                            },
                        )) catch unreachable;
                    }
                    break :_zx_whl_blk_0 _zx.ele(.fragment, .{ .children = __zx_list_0.items });
                },
            },
        },
    );
}

const zx = @import("zx");
