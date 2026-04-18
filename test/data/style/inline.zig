pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator);
    return _zx.ele(
        .div,
        .{
            .allocator = allocator,
            .attributes = _zx.attrs(.{
                _zx.attr("style", .{ .display = .flex, .padding_top = .px(10), .width = .px(100) }),
            }),
            .children = &.{
                _zx.txt(" Hello"),
            },
        },
    );
}

const zx = @import("zx");
