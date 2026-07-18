pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .div,
        .{
            .allocator = allocator,
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
                            _zx.txt("  |  "),
                        },
                    },
                ),
                _zx.ele(
                    .span,
                    .{
                        .children = &.{
                            _zx.txt("|"),
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
                            _zx.txt("|"),
                        },
                    },
                ),
                _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("hello world"),
                        },
                    },
                ),
                _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt(" hello "),
                        },
                    },
                ),
                _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("hello world"),
                        },
                    },
                ),
                _zx.ele(
                    .a,
                    .{
                        .children = &.{
                            _zx.txt("left"),
                        },
                    },
                ),
                _zx.txt(" "),
                _zx.ele(
                    .a,
                    .{
                        .children = &.{
                            _zx.txt("right"),
                        },
                    },
                ),
                _zx.ele(
                    .b,
                    .{
                        .children = &.{
                            _zx.txt("no"),
                        },
                    },
                ),
                _zx.ele(
                    .b,
                    .{
                        .children = &.{
                            _zx.txt("space"),
                        },
                    },
                ),
            },
        },
    );
}

const zx = @import("zx");
