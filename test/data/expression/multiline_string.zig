pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.expr(
                    \\ ZX
                    \\ Multiline
                ),
            },
        },
    );
}

const zx = @import("zx");
