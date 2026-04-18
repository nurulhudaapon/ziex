pub fn Page(allocator: zx.Allocator) zx.Component {
    const is_logged_in = true;
    const is_premium = false;
    var _zx = @import("zx").x.allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                if (is_logged_in) _zx.ele(
                    .fragment,
                    .{
                        .children = &.{
                            (if (is_premium) _zx.ele(
                                .p,
                                .{
                                    .children = &.{
                                        _zx.txt("Welcome, Premium User!"),
                                    },
                                },
                            ) else _zx.ele(
                                .p,
                                .{
                                    .children = &.{
                                        _zx.txt("Welcome, User!"),
                                    },
                                },
                            )),
                        },
                    },
                ) else _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Please log in to continue."),
                        },
                    },
                ),
            },
        },
    );
}

const zx = @import("zx");
