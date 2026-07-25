pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                _zx.ele(
                    .br,
                    .{},
                ),
                _zx.ele(
                    .hr,
                    .{},
                ),
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr(@src(), "type", "text"),
                            _zx.attr(@src(), "name", "username"),
                        }),
                    },
                ),
                _zx.ele(
                    .img,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr(@src(), "src", "/logo.png"),
                            _zx.attr(@src(), "alt", "Logo"),
                        }),
                    },
                ),
                _zx.ele(
                    .meta,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr(@src(), "charset", "utf-8"),
                        }),
                    },
                ),
            }),
        },
    );
}

const zx = @import("zx");
