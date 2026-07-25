pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .div,
        .{
            .allocator = allocator,
            .attributes = _zx.attrs(.{
                _zx.attr(@src(), "style", .{ .display = .flex, .padding_top = .px(10), .width = .px(100) }),
            }),
            .children = _zx.chs(.{
                _zx.txt("Hello"),
            }),
        },
    );
}

const zx = @import("zx");
