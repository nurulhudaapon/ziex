pub fn Page(allocator: zx.Allocator) zx.Component {
    var i: usize = 0;
    var j: usize = 0;

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
                                    _zx_whl_blk_1: {
                                        var __zx_list_1 = @import("std").ArrayList(@import("zx").Component).empty;
                                        while (j < 2) : (j += 1) {
                                            __zx_list_1.append(_zx.getAlloc(), _zx.ele(
                                                .p,
                                                .{
                                                    .children = &.{
                                                        _zx.expr(i * 10 + j),
                                                    },
                                                },
                                            )) catch unreachable;
                                        }
                                        break :_zx_whl_blk_1 _zx.ele(.fragment, .{ .children = __zx_list_1.items });
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
