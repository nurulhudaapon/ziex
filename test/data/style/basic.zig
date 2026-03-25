pub fn Page(allocator: zx.Allocator) zx.Component {
    const style: zx.Style = .{
        .display = .flex,
        .background_color = .hex(0xff0000),
    };
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .div,
        .{
            .allocator = allocator,
            .attributes = _zx.attrs(.{
                _zx.attr("style", style),
            }),
            .children = &.{
                _zx.txt(" Hello "),
            },
        },
    );
}

const zx = @import("zx");
