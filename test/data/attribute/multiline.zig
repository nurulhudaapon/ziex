pub fn Page(allocator: zx.Allocator) zx.Component {
    const class_name = "container";
    const is_active = true;

    var _zx = @import("zx").x.allocInit(allocator);
    return _zx.ele(
        .div,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.ele(
                    .section,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("class", class_name),
                            _zx.attr("id", "main"),
                            _zx.attr("data-active", is_active),
                        }),
                        .children = &.{
                            _zx.ele(
                                .p,
                                .{
                                    .children = &.{
                                        _zx.txt("Multiline attributes"),
                                    },
                                },
                            ),
                        },
                    },
                ),
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("type", "text"),
                            _zx.attr("class", "input"),
                            _zx.attr("placeholder", "Enter text"),
                        }),
                    },
                ),
                _zx.ele(
                    .button,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("class", "btn"),
                            _zx.attr("id", "submit"),
                        }),
                        .children = &.{
                            _zx.txt("Submit"),
                        },
                    },
                ),
            },
        },
    );
}

const zx = @import("zx");
