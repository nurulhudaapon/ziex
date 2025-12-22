pub fn Page(allocator: zx.Allocator) zx.Component {
    const is_logged_in = false;
    const user_name = if (is_logged_in) "zx" else null;

    var _zx = zx.allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                if (user_name) |un| _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.expr(un),
                        },
                    },
                ) else _zx.ele(.fragment, .{}),
            },
        },
    );
}

const zx = @import("zx");
