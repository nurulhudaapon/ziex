pub fn Page(allocator: zx.Allocator) zx.Component {
    const class_name = "container";

    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .div,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                _zx.ele(
                    .section,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr(@src(), "class", class_name),
                            _zx.attr(@src(), "id", "main"),
                            _zx.attr(@src(), "data-active", "true"),
                        }),
                        .children = _zx.chs(.{
                            _zx.ele(
                                .p,
                                .{
                                    .children = _zx.chs(.{
                                        _zx.txt("Messy indentation"),
                                    }),
                                },
                            ),
                        }),
                    },
                ),
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr(@src(), "type", "text"),
                            _zx.attr(@src(), "class", "input"),
                            _zx.attr(@src(), "placeholder", "Enter text"),
                        }),
                    },
                ),
            }),
        },
    );
}

const zx = @import("zx");
