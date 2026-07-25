pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.cmp(
        Button,
        .{ .src = @src() },
        .{ .name = "Button" },
        .{},
    );
}

pub fn Button(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .button,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                _zx.txt("Button"),
            }),
        },
    );
}

const zx = @import("zx");
