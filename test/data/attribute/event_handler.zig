pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = zx.allocInit(allocator);
    return _zx.ele(
        .fragment,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.ele(
                    .button,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("onclick", handleClick),
                        }),
                        .children = &.{
                            _zx.txt(" Click me"),
                        },
                    },
                ),
            },
        },
    );
}

fn handleClick(event: zx.EventContext) void {
    _ = event;
    std.debug.print("handleClick\n", .{});
}

const zx = @import("zx");
const std = @import("std");
