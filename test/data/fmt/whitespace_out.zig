pub fn FmtWhitespace(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.init(.{ .src = @src() });
    return _zx.ele(
        .div,
        .{
            .children = _zx.chs(.{
                _zx.ele(
                    .span,
                    .{
                        .children = _zx.chs(.{
                            _zx.txt("| "),
                        }),
                    },
                ),
                _zx.ele(
                    .span,
                    .{
                        .children = _zx.chs(.{
                            _zx.txt(" |"),
                        }),
                    },
                ),
                _zx.ele(
                    .span,
                    .{
                        .children = _zx.chs(.{
                            _zx.txt(" | "),
                        }),
                    },
                ),
                _zx.ele(
                    .span,
                    .{
                        .children = _zx.chs(.{
                            _zx.txt("| "),
                        }),
                    },
                ),
                _zx.ele(
                    .span,
                    .{
                        .children = _zx.chs(.{
                            _zx.txt(" |"),
                        }),
                    },
                ),
                _zx.ele(
                    .span,
                    .{
                        .children = _zx.chs(.{
                            _zx.txt(" | "),
                        }),
                    },
                ),
                _zx.ele(
                    .span,
                    .{
                        .children = _zx.chs(.{
                            _zx.txt("|"),
                        }),
                    },
                ),
                _zx.ele(
                    .span,
                    .{
                        .children = _zx.chs(.{
                            _zx.txt(" | "),
                        }),
                    },
                ),
                _zx.ele(
                    .p,
                    .{
                        .children = _zx.chs(.{
                            _zx.txt("hello"),
                        }),
                    },
                ),
                _zx.ele(
                    .p,
                    .{
                        .children = _zx.chs(.{
                            _zx.txt(" hello "),
                        }),
                    },
                ),
            }),
        },
    );
}

const zx = @import("zx");
