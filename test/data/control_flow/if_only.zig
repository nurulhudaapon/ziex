pub fn Page(allocator: zx.Allocator) zx.Component {
    const is_logged_in = false;
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                if (is_logged_in) _zx.ele(
                    .p,
                    .{
                        .children = _zx.chs(.{
                            _zx.txt("Welcome, User!"),
                        }),
                    },
                ) else _zx.ele(.fragment, .{}),
                _zx.ele(
                    .div,
                    .{
                        .children = _zx.chs(.{
                            if (is_logged_in) _zx.txt("Welcome, User!") else _zx.ele(.fragment, .{}),
                        }),
                    },
                ),
            }),
        },
    );
}

const zx = @import("zx");
