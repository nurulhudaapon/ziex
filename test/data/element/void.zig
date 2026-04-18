pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
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
                            _zx.attr("type", "text"),
                            _zx.attr("name", "username"),
                        }),
                    },
                ),
                _zx.ele(
                    .img,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("src", "/logo.png"),
                            _zx.attr("alt", "Logo"),
                        }),
                    },
                ),
                _zx.ele(
                    .meta,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("charset", "utf-8"),
                        }),
                    },
                ),
            },
        },
    );
}

const zx = @import("zx");
