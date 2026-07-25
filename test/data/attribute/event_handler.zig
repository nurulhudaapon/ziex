pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .fragment,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                _zx.ele(
                    .button,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr(@src(), "onclick", handleClick),
                        }),
                        .children = _zx.chs(.{
                            _zx.txt("Click me"),
                        }),
                    },
                ),
            }),
        },
    );
}

fn handleClick(event: zx.client.Event) void {
    _ = event;
    std.debug.print("handleClick\n", .{});
}

const zx = @import("zx");
const std = @import("std");
