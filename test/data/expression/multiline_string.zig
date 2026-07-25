pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                _zx.expr(
                    \\ ZX
                    \\ Multiline
                ),
            }),
        },
    );
}

const zx = @import("zx");
