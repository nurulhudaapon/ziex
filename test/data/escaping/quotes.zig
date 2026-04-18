pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator);
    return _zx.ele(
        .div,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.txt(" quote should be escaped "),
                _zx.ele(
                    .code,
                    .{
                        .children = &.{
                            _zx.txt("\"quote\""),
                        },
                    },
                ),
                _zx.ele(
                    .pre,
                    .{
                        .children = &.{
                            _zx.txt("\"quote\""),
                        },
                    },
                ),
            },
        },
    );
}

const zx = @import("zx");
