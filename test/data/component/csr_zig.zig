pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.cmp(
                    CounterComponent,
                    "CounterComponent",
                    .{ .client = .{ .name = "CounterComponent", .id = "c8fee6a" } },
                    .{},
                ),
                _zx.cmp(
                    CounterComponent,
                    "CounterComponent",
                    .{},
                    .{},
                ),
                _zx.cmp(
                    Button,
                    "Button",
                    .{ .client = .{ .name = "Button", .id = "cd02624" } },
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
