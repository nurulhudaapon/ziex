pub fn Page(allocator: zx.Allocator) zx.Component {
    const @"data-name" = "hello";
    const value: i32 = 42;
    const class = "b-1 bold";

    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .form,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr(@src(), "data-name", @"data-name"),
                            _zx.attr(@src(), "class", class),
                        }),
                    },
                ),
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr(@src(), "value", value),
                        }),
                    },
                ),
            }),
        },
    );
}

const zx = @import("zx");
