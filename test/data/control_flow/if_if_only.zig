pub fn Page(allocator: zx.Allocator) zx.Component {
    const is_logged_in = true;
    const is_premium = true;

    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                _zx.ele(
                    .p,
                    .{
                        .children = _zx.chs(.{
                            _zx.txt("Welcome, User!"),
                        }),
                    },
                ),
                if (is_logged_in) _zx.ele(
                    .fragment,
                    .{
                        .children = _zx.chs(.{
                            (if (is_premium) _zx.ele(
                                .p,
                                .{
                                    .children = _zx.chs(.{
                                        _zx.txt("Welcome, Premium User!"),
                                    }),
                                },
                            ) else _zx.ele(.fragment, .{})),
                        }),
                    },
                ) else _zx.ele(.fragment, .{}),
            }),
        },
    );
}

const zx = @import("zx");
