pub fn Page(allocator: zx.Allocator) zx.Component {
    const greeting = zx.Component{ .text = "Hello!" };

    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .section,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                _zx.ele(
                    .p,
                    .{
                        .children = _zx.chs(.{
                            _zx.txt("Greeting: "),
                            _zx.expr(greeting),
                        }),
                    },
                ),
                _zx.ele(
                    .div,
                    .{
                        .children = _zx.chs(.{
                            _zx.expr(greeting),
                        }),
                    },
                ),
            }),
        },
    );
}

const zx = @import("zx");
