pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .div,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                _zx.txt("quote should be escaped"),
                _zx.ele(
                    .code,
                    .{
                        .children = _zx.chs(.{
                            _zx.txt("\"quote\""),
                        }),
                    },
                ),
                _zx.ele(
                    .pre,
                    .{
                        .children = _zx.chs(.{
                            _zx.txt("\"quote\""),
                        }),
                    },
                ),
            }),
        },
    );
}

const zx = @import("zx");
