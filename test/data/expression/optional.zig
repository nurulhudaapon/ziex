pub fn Page(allocator: zx.Allocator) zx.Component {
    const maybe_name: ?[]const u8 = "Alice";
    const no_name: ?[]const u8 = null;

    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                _zx.ele(
                    .p,
                    .{
                        .children = _zx.chs(.{
                            _zx.txt("Name: "),
                            _zx.expr(maybe_name orelse "Guest"),
                        }),
                    },
                ),
                _zx.ele(
                    .p,
                    .{
                        .children = _zx.chs(.{
                            _zx.txt("Default: "),
                            _zx.expr(no_name orelse "Anonymous"),
                        }),
                    },
                ),
            }),
        },
    );
}

const zx = @import("zx");
