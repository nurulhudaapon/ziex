pub fn Page(allocator: zx.Allocator) zx.Component {
    const @"data-name" = "hello";
    const value: i32 = 42;
    const class = "b-1 bold";

    var _zx = zx.allocInit(allocator);
    return _zx.ele(
        .form,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("data-name", @"data-name"),
                            _zx.attr("class", class),
                        }),
                    },
                ),
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("value", value),
                        }),
                    },
                ),
            },
        },
    );
}

const zx = @import("zx");
