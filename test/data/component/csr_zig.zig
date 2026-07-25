pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                _zx.cmp(
                    CounterComponent,
                    .{ .src = @src() },
                    .{ .name = "CounterComponent", .client = .{ .name = "CounterComponent", .id = "c8fee6a" } },
                    .{},
                ),
                _zx.cmp(
                    CounterComponent,
                    .{ .src = @src() },
                    .{ .name = "CounterComponent" },
                    .{},
                ),
                _zx.cmp(
                    Button,
                    .{ .src = @src() },
                    .{ .name = "Button", .client = .{ .name = "Button", .id = "cd02624" } },
                    .{ .title = "Custom Button" },
                ),
            }),
        },
    );
}

pub fn CounterComponent(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .button,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                _zx.txt("Counter"),
            }),
        },
    );
}

const Button = @import("basic.zig").Button;
const zx = @import("zx");
