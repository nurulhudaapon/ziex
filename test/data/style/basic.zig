pub fn Page(allocator: std.mem.Allocator) zx.Component {
    const style = zx.style.styleInit(.{
        zx.style.display(.flex),
        zx.style.flex_direction(.column),
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
                _zx.txt(" Basic style"),
            },
        },
    );
}

const std = @import("std");
const zx = @import("zx");
