pub fn Page(allocator: zx.Allocator) zx.Component {
    const is_logged_in = false;
    const is_premium = false;
    const is_pro = false;
    const is_enterprise = false;
    const is_trial = false;
    const is_guest = false;

    var _zx = zx.allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                if (is_logged_in) _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Welcome, User!"),
                        },
                    },
                ) else if (is_premium) _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Welcome, Premium User!"),
                        },
                    },
                ) else if (is_pro) _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Welcome, Pro User!"),
                        },
                    },
                ) else if (is_enterprise) _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Welcome, Enterprise User!"),
                        },
                    },
                ) else if (is_trial) _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Welcome, Trial User!"),
                        },
                    },
                ) else if (is_guest) _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Welcome, Guest!"),
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
