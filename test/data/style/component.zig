pub fn Page(allocator: std.mem.Allocator) zx.Component {
    const style = zx.style.styleInit(.{
        zx.style.color(.hex(0x0000ff)),
        zx.style.margin_top(.px(20)),
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
                _zx.txt(" Component style"),
            },
        },
    );
}

const std = @import("std");
const zx = @import("zx");
