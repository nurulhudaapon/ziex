pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = zx.initWithAllocator(allocator);
    return _zx.zx(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.lazy(Button, .{ .title = "Custom Button" }),
            },
        },
    );
}

const zx = @import("zx");
const Button = @import("basic.zig").Button;

// const ClientComponent = @jsImport("basic.tsx");
