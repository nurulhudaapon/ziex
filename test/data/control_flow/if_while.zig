pub fn Page(allocator: zx.Allocator) zx.Component {
    const show_list = true;
    var i: usize = 0;

    var _zx = @import("zx").x.allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                if (show_list) _zx.ele(
                    .div,
                    .{
                        .children = &.{
                            _zx_whl_blk_0: {
                                var __zx_list_0 = @import("std").ArrayList(@import("zx").Component).empty;
                                while (i < 3) : (i += 1) {
                                    __zx_list_0.append(_zx.getAlloc(), _zx.ele(
                                        .p,
                                        .{
                                            .children = &.{
                                                _zx.expr(i),
                                            },
                                        },
                                    )) catch unreachable;
                                }
                                break :_zx_whl_blk_0 _zx.ele(.fragment, .{ .children = __zx_list_0.items });
                            },
                        },
                    },
                ) else _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("List hidden"),
                        },
                    },
                ),
            },
        },
    );
}

const zx = @import("zx");
