pub fn Page(allocator: std.mem.Allocator) zx.Component {
    const s = zx.style;
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .div,
        .{
            .allocator = allocator,
            .attributes = _zx.attrs(.{
                _zx.attr("style", s.styleInit(.{ s.display(.flex), s.row_gap(.px(10)) })),
            }),
            .children = &.{
                _zx.ele(
                    .span,
                    .{
                        .children = &.{
                            _zx.txt("Item 1"),
                        },
                    },
                ),
                _zx.ele(
                    .span,
                    .{
                        .children = &.{
                            _zx.txt("Item 2"),
                        },
                    },
                ),
            },
        },
    );
}

const std = @import("std");
const zx = @import("zx");
