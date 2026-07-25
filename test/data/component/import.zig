pub fn Page(allocator: z.Allocator) z.Component {
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                _zx.cmp(
                    Button,
                    .{ .src = @src() },
                    .{ .name = "Button" },
                    .{ .title = "Custom Button" },
                ),
            }),
        },
    );
}

const z = @import("zx");
const Button = @import("basic.zig").Button;
