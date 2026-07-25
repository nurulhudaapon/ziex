pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                _zx.ele(
                    .fragment,
                    .{
                        .children = _zx.chs(.{
                            _zx.ele(
                                .p,
                                .{
                                    .children = _zx.chs(.{
                                        _zx.txt("First"),
                                    }),
                                },
                            ),
                            _zx.ele(
                                .p,
                                .{
                                    .children = _zx.chs(.{
                                        _zx.txt("Second"),
                                    }),
                                },
                            ),
                        }),
                    },
                ),
            }),
        },
    );
}

const zx = @import("zx");
