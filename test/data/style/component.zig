pub fn Page(allocator: zx.Allocator) zx.Component {
    const style: zx.Style = .{
        .display = .flex,
        .flex_direction = .column,
        .padding_top = .px(10),
        .width = .px(100),
    };
    var _zx = @import("zx").x.allocInit(allocator);
    return _zx.ele(
        .div,
        .{
            .allocator = allocator,
            .attributes = _zx.attrs(.{
                _zx.attr("style", style),
            }),
            .children = &.{
                _zx.txt(" Hello"),
            },
        },
    );
}

const zx = @import("zx");
