pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                _zx.ele(
                    .custom,
                    .{
                        .custom_tag = "my-widget",
                        .attributes = _zx.attrs(.{
                            _zx.attr(@src(), "class", "hero"),
                        }),
                        .children = _zx.chs(.{
                            _zx.ele(
                                .span,
                                .{
                                    .children = _zx.chs(.{
                                        _zx.txt("Hello CE"),
                                    }),
                                },
                            ),
                        }),
                    },
                ),
                _zx.ele(
                    .custom,
                    .{
                        .custom_tag = "x-button",
                        .attributes = _zx.attrs(.{
                            _zx.attr(@src(), "label", "Go"),
                        }),
                    },
                ),
            }),
        },
    );
}

const zx = @import("zx");
