pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                _zx.cmp(
                    None,
                    .{ .src = @src() },
                    .{ .name = "None" },
                    .{},
                ),
                _zx.cmp(
                    Null,
                    .{ .src = @src() },
                    .{ .name = "Null" },
                    .{},
                ),
            }),
        },
    );
}

pub fn None(_: *zx.ComponentContext) ?zx.Component {
    if (true) return .none;
}

pub fn Null(_: *zx.ComponentContext) ?zx.Component {
    if (true) return null;
}

const zx = @import("zx");
