pub fn Page(allocator: zx.Allocator) zx.Component {
    const class_name = "container";
    const is_active = true;
    const id = "main-content";

    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                _zx.ele(
                    .div,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr(@src(), "class", class_name),
                            _zx.attr(@src(), "id", id),
                        }),
                        .children = _zx.chs(.{
                            _zx.ele(
                                .button,
                                .{
                                    .attributes = _zx.attrs(.{
                                        _zx.attr(@src(), "class", if (is_active) "active" else "inactive"),
                                    }),
                                    .children = _zx.chs(.{
                                        _zx.txt("Click me"),
                                    }),
                                },
                            ),
                        }),
                    },
                ),
            }),
        },
    );
}

const zx = @import("zx");
