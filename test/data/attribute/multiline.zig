pub fn Page(allocator: zx.Allocator) zx.Component {
    const class_name = "container";
    const is_active = true;

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
                            _zx.attr(@src(), "data-active", is_active),
                        }),
                        .children = _zx.chs(.{
                            _zx.ele(
                                .p,
                                .{
                                    .children = _zx.chs(.{
                                        _zx.txt("Multiline attributes"),
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
                _zx.ele(
                    .button,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr(@src(), "class", "btn"),
                            _zx.attr(@src(), "id", "submit"),
                        }),
                        .children = _zx.chs(.{
                            _zx.txt("Submit"),
                        }),
                    },
                ),
            }),
        },
    );
}

const zx = @import("zx");
