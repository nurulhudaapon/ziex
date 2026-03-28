pub fn Page(allocator: std.mem.Allocator) zx.Component {
    const header_style = zx.style.init(.{
        @as(zx.style.StyleProperty, .{ .background_color = .hex(0x0f0f0f) }),
        @as(zx.style.StyleProperty, .{ .hover = &zx.style.init(.{
            @as(zx.style.StyleProperty, .{ .background_color = .hex(0xf0f0f0) }),
        }) }),
    });

    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .div,
        .{
            .allocator = allocator,
            .attributes = _zx.attrs(.{
                _zx.attr("style", zx.style.init(.{@as(zx.style.StyleProperty, .{ .display = .flex })})),
            }),
            .children = &.{
                _zx.ele(
                    .h1,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("style", header_style),
                        }),
                        .children = &.{
                            _zx.txt("Hello Style"),
                        },
                    },
                ),
                _zx.ele(
                    .p,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("style", zx.style.init(.{ @as(zx.style.StyleProperty, .{ .color = .hex(0xff0000) }), @as(zx.style.StyleProperty, .{ .font_weight = .bold }) })),
                        }),
                        .children = &.{
                            _zx.txt(" Universal builtin function test"),
                        },
                    },
                ),
            },
        },
    );
}

const std = @import("std");
const zx = @import("zx");
