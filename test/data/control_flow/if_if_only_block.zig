pub fn Page(allocator: zx.Allocator) zx.Component {
    const is_logged_in = true;
    const is_premium = true;
    var _zx = @import("zx").x.allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                if (is_logged_in) _zx.ele(
                    .div,
                    .{
                        .children = &.{
                            if (is_premium) _zx.ele(
                                .div,
                                .{
                                    .children = &.{
                                        _zx.ele(
                                            .p,
                                            .{
                                                .children = &.{
                                                    _zx.txt("Welcome, Premium User"),
                                                },
                                            },
                                        ),
                                    },
                                },
                            ) else _zx.ele(.fragment, .{}),
                        },
                    },
                ) else _zx.ele(.fragment, .{}),
            },
        },
    );
}

const zx = @import("zx");
