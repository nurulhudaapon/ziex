pub fn Page(allocator: zx.Allocator) zx.Component {
    const items = [_][]const u8{ "apple", "banana", "cherry" };

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
                            _zx.txt("Count: "),
                            _zx.expr(getCount()),
                        }),
                    },
                ),
                _zx.ele(
                    .p,
                    .{
                        .children = _zx.chs(.{
                            _zx.txt("Items: "),
                            _zx.expr(items.len),
                        }),
                    },
                ),
                _zx.ele(
                    .p,
                    .{
                        .children = _zx.chs(.{
                            _zx.txt("Greeting: "),
                            _zx.expr(greet("World")),
                        }),
                    },
                ),
            }),
        },
    );
}

fn getCount() u32 {
    return 42;
}

fn greet(name: []const u8) []const u8 {
    _ = name;
    return "Hello!";
}

const zx = @import("zx");
