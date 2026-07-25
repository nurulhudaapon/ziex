pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                _zx.ele(
                    .h1,
                    .{
                        .children = _zx.chs(.{
                            _zx.txt("Welcome to the site!"),
                        }),
                    },
                ),
            }),
        },
    );
}

const zx = @import("zx");
