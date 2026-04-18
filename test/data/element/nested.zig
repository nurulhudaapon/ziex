pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.ele(
                    .div,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("class", "container"),
                        }),
                        .children = &.{
                            _zx.ele(
                                .header,
                                .{
                                    .children = &.{
                                        _zx.ele(
                                            .nav,
                                            .{
                                                .children = &.{
                                                    _zx.ele(
                                                        .ul,
                                                        .{
                                                            .children = &.{
                                                                _zx.ele(
                                                                    .li,
                                                                    .{
                                                                        .children = &.{
                                                                            _zx.ele(
                                                                                .a,
                                                                                .{
                                                                                    .attributes = _zx.attrs(.{
                                                                                        _zx.attr("href", "/"),
                                                                                    }),
                                                                                    .children = &.{
                                                                                        _zx.txt("Home"),
                                                                                    },
                                                                                },
                                                                            ),
                                                                        },
                                                                    },
                                                                ),
                                                                _zx.ele(
                                                                    .li,
                                                                    .{
                                                                        .children = &.{
                                                                            _zx.ele(
                                                                                .a,
                                                                                .{
                                                                                    .attributes = _zx.attrs(.{
                                                                                        _zx.attr("href", "/about"),
                                                                                    }),
                                                                                    .children = &.{
                                                                                        _zx.txt("About"),
                                                                                    },
                                                                                },
                                                                            ),
                                                                        },
                                                                    },
                                                                ),
                                                            },
                                                        },
                                                    ),
                                                },
                                            },
                                        ),
                                    },
                                },
                            ),
                            _zx.ele(
                                .article,
                                .{
                                    .children = &.{
                                        _zx.ele(
                                            .section,
                                            .{
                                                .children = &.{
                                                    _zx.ele(
                                                        .p,
                                                        .{
                                                            .children = &.{
                                                                _zx.txt("Deeply nested content"),
                                                            },
                                                        },
                                                    ),
                                                },
                                            },
                                        ),
                                    },
                                },
                            ),
                        },
                    },
                ),
            },
        },
    );
}

const zx = @import("zx");
