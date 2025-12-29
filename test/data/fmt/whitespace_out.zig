pub fn FmtWhitespace(allocator: zx.Allocator) zx.Component {
    var _zx = zx.init();
    return _zx.ele(
        .div,
        .{
            .children = &.{
                _zx.ele(
                    .span,
                    .{
                        .children = &.{
                            _zx.txt("| "),
                        },
                    },
                ),
                _zx.ele(
                    .span,
                    .{
                        .children = &.{
                            _zx.txt(" |"),
                        },
                    },
                ),
                _zx.ele(
                    .span,
                    .{
                        .children = &.{
                            _zx.txt(" | "),
                        },
                    },
                ),
                _zx.ele(
                    .span,
                    .{
                        .children = &.{
                            _zx.txt("| "),
                        },
                    },
                ),
                _zx.ele(
                    .span,
                    .{
                        .children = &.{
                            _zx.txt(" |"),
                        },
                    },
                ),
                _zx.ele(
                    .span,
                    .{
                        .children = &.{
                            _zx.txt(" | "),
                        },
                    },
                ),
                _zx.ele(
                    .span,
                    .{
                        .children = &.{
                            _zx.txt(" |"),
                        },
                    },
                ),
            },
        },
    );
}

const zx = @import("zx");
