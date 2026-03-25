pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .div,
        .{
            .allocator = allocator,
            .attributes = _zx.attrs(.{
                _zx.attr("style", zx.Style{ .display = .flex, .row_gap = .px(10) }),
            }),
            .children = &.{
                _zx.txt(" Inline Style "),
            },
        },
    );
}

const zx = @import("zx");
