pub fn Page(allocator: zx.Allocator) zx.Component {
    const show_list = true;
    const items = [_][]const u8{ "Apple", "Banana", "Cherry" };
    var i: usize = 0;

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
                            _zx_whl_blk_0: {
                                var __zx_list_0 = @import("std").ArrayList(@import("zx").Component).empty;
                                while (i < 3) : (i += 1) {
                                    __zx_list_0.append(_zx.getAlloc(), _zx.ele(
                                        .li,
                                        .{
                                            .children = _zx.chs(.{
                                                if (items[i].len > 5) _zx.ele(
                                                    .strong,
                                                    .{
                                                        .children = _zx.chs(.{
                                                            _zx.expr(items[i]),
                                                        }),
                                                    },
                                                ) else _zx.ele(
                                                    .span,
                                                    .{
                                                        .children = _zx.chs(.{
                                                            _zx.expr(items[i]),
                                                        }),
                                                    },
                                                ),
                                            }),
                                        },
                                    )) catch unreachable;
                                }
                                break :_zx_whl_blk_0 _zx.ele(.fragment, .{ .children = __zx_list_0.items });
                            },
                        }),
                    },
                ) else _zx.ele(
                    .p,
                    .{
                        .children = _zx.chs(.{
                            _zx.txt("List hidden"),
                        }),
                    },
                ),
            }),
        },
    );
}

const zx = @import("zx");
