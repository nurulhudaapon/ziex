pub fn Page(allocator: zx.Allocator) zx.Component {
    var i: usize = 0;

    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                _zx_whl_blk_0: {
                    var __zx_list_0 = @import("std").ArrayList(@import("zx").Component).empty;
                    while (i < 3) : (i += 1) {
                        __zx_list_0.append(_zx.getAlloc(), _zx.ele(
                            .div,
                            .{
                                .children = _zx.chs(.{
                                    switch (i) {
                                        0 => _zx.ele(
                                            .span,
                                            .{
                                                .children = _zx.chs(.{
                                                    _zx.txt("Zero"),
                                                }),
                                            },
                                        ),
                                        1 => _zx.ele(
                                            .span,
                                            .{
                                                .children = _zx.chs(.{
                                                    _zx.txt("One"),
                                                }),
                                            },
                                        ),
                                        else => _zx.ele(
                                            .span,
                                            .{
                                                .children = _zx.chs(.{
                                                    _zx.txt("Other"),
                                                }),
                                            },
                                        ),
                                    },
                                }),
                            },
                        )) catch unreachable;
                    }
                    break :_zx_whl_blk_0 _zx.ele(.fragment, .{ .children = __zx_list_0.items });
                },
            }),
        },
    );
}

const zx = @import("zx");
