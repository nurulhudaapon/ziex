pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = zx.allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.cmp(
                    CounterComponent,
                    .{ .client = .{ .name = "CounterComponent", .id = "zx-2676a2f99c98f8f91dd890d002af04ba-0" } },
                    .{},
                ),
                _zx.cmp(
                    CounterComponent,
                    .{},
                    .{},
                ),
                _zx.cmp(
                    Button,
                    .{ .client = .{ .name = "Button", .id = "zx-c6f40e3ab2f0caeebf36ba66712cc7fe-1" } },
                    .{ .title = "Custom Button" },
                ),
            },
        },
    );
}

pub fn CounterComponent(allocator: zx.Allocator) zx.Component {
    var _zx = zx.allocInit(allocator);
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
