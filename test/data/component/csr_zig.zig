pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.cmp(
                    CounterComponent,
                    .{ .name = "CounterComponent", .client = .{ .name = "CounterComponent", .id = "c8fee6a" } },
                    .{},
                ),
                _zx.cmp(
                    CounterComponent,
                    .{ .name = "CounterComponent" },
                    .{},
                ),
                _zx.cmp(
                    Button,
                    .{ .name = "Button", .client = .{ .name = "Button", .id = "cd02624" } },
                    .{ .title = "Custom Button" },
                ),
            },
        },
    );
}

pub fn CounterComponent(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .button,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.txt("Counter"),
            },
        },
    );
}

const Button = @import("basic.zig").Button;
const zx = @import("zx");
