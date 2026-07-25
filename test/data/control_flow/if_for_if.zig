pub fn Page(allocator: zx.Allocator) zx.Component {
    const show_list = true;
    const items = [_][]const u8{ "Apple", "Banana", "Cherry" };

    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                if (show_list) _zx.ele(
                    .ul,
                    .{
                        .children = _zx.chs(.{
                            _zx_for_blk_0: {
                                const __zx_children_0 = _zx.getAlloc().alloc(@import("zx").Component, items.len) catch unreachable;
                                for (items, 0..) |item, _zx_i_0| {
                                    __zx_children_0[_zx_i_0] = _zx.ele(
                                        .li,
                                        .{
                                            .children = _zx.chs(.{
                                                if (item.len > 5) _zx.ele(
                                                    .strong,
                                                    .{
                                                        .children = _zx.chs(.{
                                                            _zx.expr(item),
                                                        }),
                                                    },
                                                ) else _zx.ele(
                                                    .span,
                                                    .{
                                                        .children = _zx.chs(.{
                                                            _zx.expr(item),
                                                        }),
                                                    },
                                                ),
                                            }),
                                        },
                                    );
                                }
                                break :_zx_for_blk_0 _zx.ele(.fragment, .{ .children = __zx_children_0 });
                            },
                        }),
                    },
                ) else _zx.ele(
                    .p,
                    .{
                        .children = _zx.chs(.{
                            _zx.txt("No items"),
                        }),
                    },
                ),
            }),
        },
    );
}

const zx = @import("zx");
