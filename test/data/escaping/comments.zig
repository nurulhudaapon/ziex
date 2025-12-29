pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = zx.allocInit(allocator);
    return _zx.ele(
        .section,
        .{
            .allocator = allocator,
            .attributes = _zx.attrs(.{
                _zx.attr("data-src", @src().file),
            }),
            .children = &.{},
        },
    );
}

const zx = @import("zx");
