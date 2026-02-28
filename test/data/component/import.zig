pub fn Page(allocator: z.Allocator) z.Component {
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.cmp(
                    Button,
                    "Button",
                    .{},
                    .{ .title = "Custom Button" },
                ),
            },
        },
    );
}

const z = @import("zx");
const Button = @import("basic.zig").Button;

// const ClientComponent = @jsImport("basic.tsx");
