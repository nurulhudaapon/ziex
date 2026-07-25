pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                _zx.ele(
                    .div,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr(@src(), "class", "container"),
                        }),
                        .children = _zx.chs(.{
                            _zx.ele(
                                .header,
                                .{
                                    .children = _zx.chs(.{
                                        _zx.ele(
                                            .nav,
                                            .{
                                                .children = _zx.chs(.{
                                                    _zx.ele(
                                                        .ul,
                                                        .{
                                                            .children = _zx.chs(.{
                                                                _zx.ele(
                                                                    .li,
                                                                    .{
                                                                        .children = _zx.chs(.{
                                                                            _zx.ele(
                                                                                .a,
                                                                                .{
                                                                                    .attributes = _zx.attrs(.{
                                                                                        _zx.attr(@src(), "href", "/"),
                                                                                    }),
                                                                                    .children = _zx.chs(.{
                                                                                        _zx.txt("Home"),
                                                                                    }),
                                                                                },
                                                                            ),
                                                                        }),
                                                                    },
                                                                ),
                                                                _zx.ele(
                                                                    .li,
                                                                    .{
                                                                        .children = _zx.chs(.{
                                                                            _zx.ele(
                                                                                .a,
                                                                                .{
                                                                                    .attributes = _zx.attrs(.{
                                                                                        _zx.attr(@src(), "href", "/about"),
                                                                                    }),
                                                                                    .children = _zx.chs(.{
                                                                                        _zx.txt("About"),
                                                                                    }),
                                                                                },
                                                                            ),
                                                                        }),
                                                                    },
                                                                ),
                                                            }),
                                                        },
                                                    ),
                                                }),
                                            },
                                        ),
                                    }),
                                },
                            ),
                            _zx.ele(
                                .article,
                                .{
                                    .children = _zx.chs(.{
                                        _zx.ele(
                                            .section,
                                            .{
                                                .children = _zx.chs(.{
                                                    _zx.ele(
                                                        .p,
                                                        .{
                                                            .children = _zx.chs(.{
                                                                _zx.txt("Deeply nested content"),
                                                            }),
                                                        },
                                                    ),
                                                }),
                                            },
                                        ),
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
