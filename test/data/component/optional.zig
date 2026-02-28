pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.cmp(
                    None,
                    .{ .name = "None" },
                    .{},
                ),
                _zx.cmp(
                    Null,
                    .{ .name = "Null" },
                    .{},
                ),
            },
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
