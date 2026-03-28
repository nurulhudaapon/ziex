pub fn Page(allocator: zx.Allocator) zx.Component {
    const style = zx.style.init(.{
        ..Page(allocator: (unknown type))
    });
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .div,
        .{
            .allocator = allocator,
            .attributes = _zx.attrs(.{
                _zx.attr("style", style),
            }),
            .children = &.{
                _zx.txt("Hello"),
            },
        },
    );
}

const zx = @import("zx");
