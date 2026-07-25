pub fn Page(allocator: zx.Allocator) zx.Component {
    const mode: Mode = .repeat;
    var i: usize = 0;

    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                switch (mode) {
                    .single => _zx.ele(
                        .p,
                        .{
                            .children = _zx.chs(.{
                                _zx.txt("Single"),
                            }),
                        },
                    ),
                    .repeat => _zx_whl_blk_0: {
                        var __zx_list_0 = @import("std").ArrayList(@import("zx").Component).empty;
                        while (i < 3) : (i += 1) {
                            __zx_list_0.append(_zx.getAlloc(), _zx.ele(
                                .p,
                                .{
                                    .children = _zx.chs(.{
                                        _zx.expr(i),
                                    }),
                                },
                            )) catch unreachable;
                        }
                        break :_zx_whl_blk_0 _zx.ele(.fragment, .{ .children = __zx_list_0.items });
                    },
                },
            }),
        },
    );
}

const zx = @import("zx");

const Mode = enum { single, repeat };
