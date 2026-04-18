pub fn Page(allocator: zx.Allocator) zx.Component {
    const user = "John Doe";
    const user_empty = "";

    var _zx = @import("zx").x.allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                if (try_get_user(user)) |u| _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Welcome, "),
                            _zx.expr(u),
                            _zx.txt("!"),
                        },
                    },
                ) else |err| _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Error: "),
                            _zx.expr(@errorName(err)),
                        },
                    },
                ),
                if (try_get_user(user_empty)) |u| _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Welcome, "),
                            _zx.expr(u),
                            _zx.txt("!"),
                        },
                    },
                ) else |err| _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Error: "),
                            _zx.expr(@errorName(err)),
                        },
                    },
                ),
            },
        },
    );
}

fn try_get_user(user: []const u8) error{UserNotFound}![]const u8 {
    return if (user.len > 0) user else error.UserNotFound;
}

const zx = @import("zx");
