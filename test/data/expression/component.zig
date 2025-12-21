pub fn Page(allocator: zx.Allocator) zx.Component {
    const greeting = zx.Component{ .text = "Hello!" };

    var _zx = zx.allocInit(allocator);
    return _zx.ele(
        .section,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Greeting: "),
                            _zx.expr(greeting),
                        },
                    },
                ),
                _zx.ele(
                    .div,
                    .{
                        .children = &.{
                            _zx.expr(greeting),
                        },
                    },
                ),
            },
        },
    );
}

const zx = @import("zx");
