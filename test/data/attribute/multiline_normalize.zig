pub fn Page(allocator: zx.Allocator) zx.Component {
    const class_name = "container";

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
                            _zx.attr("data-active", "true"),
                        }),
                        .children = &.{
                            _zx.ele(
                                .p,
                                .{
                                    .children = &.{
                                        _zx.txt("Messy indentation"),
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
            },
        },
    );
}

const zx = @import("zx");
