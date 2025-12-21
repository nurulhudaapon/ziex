pub fn Page(allocator: zx.Allocator) zx.Component {
    const is_logged_in = true;
    const is_premium = true;

    var _zx = zx.initWithAllocator(allocator);
    return _zx.zx(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.zx(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Welcome, User!"),
                        },
                    },
                ),
                if (is_logged_in) _zx.zx(
                    .fragment,
                    .{
                        .children = &.{
                            (if (is_premium) _zx.zx(
                                .p,
                                .{
                                    .children = &.{
                                        _zx.txt("Welcome, Premium User!"),
                                    },
                                },
                            ) else _zx.zx(.fragment, .{})),
                        },
                    },
                ) else _zx.zx(.fragment, .{}),
            },
        },
    );
}

const zx = @import("zx");
