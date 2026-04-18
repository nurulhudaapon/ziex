pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator);
    return _zx.ele(
        .section,
        .{
            .allocator = allocator,
            .attributes = _zx.attrs(.{
                _zx.attr("data-src", @src().file),
            }),
            .children = &.{},
        },
    );
}

pub fn Comments(_: zx.ComponentContext) zx.Component {
    var _zx = @import("zx").x.init();
    return _zx.ele(
        .div,
        .{
            .children = &.{
                _zx.ele(
                    .section,
                    .{
                        .children = &.{},
                    },
                ),
            },
        },
    );
}

pub fn EmptyComments(_: zx.ComponentContext) zx.Element {
    var _zx = @import("zx").x.init();
    return _zx.ele(
        .div,
        .{
            .children = &.{
                _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Content after empty comments"),
                        },
                    },
                ),
            },
        },
    );
}

pub fn CommentsWithSpecialChars(_: zx.ComponentContext) zx.Element {
    var _zx = @import("zx").x.init();
    return _zx.ele(
        .div,
        .{
            .children = &.{
                _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("After special char comments"),
                        },
                    },
                ),
            },
        },
    );
}

pub fn CommentsWithExpressions(_: zx.ComponentContext) zx.Element {
    const value = "test";
    var _zx = @import("zx").x.init();
    return _zx.ele(
        .div,
        .{
            .children = &.{
                _zx.ele(
                    .p,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("data-value", value),
                        }),
                        .children = &.{
                            _zx.txt("Actual content"),
                        },
                    },
                ),
            },
        },
    );
}

pub fn NestedComments(_: zx.ComponentContext) zx.Element {
    var _zx = @import("zx").x.init();
    return _zx.ele(
        .div,
        .{
            .children = &.{
                _zx.ele(
                    .section,
                    .{
                        .children = &.{
                            _zx.ele(
                                .article,
                                .{
                                    .children = &.{
                                        _zx.ele(
                                            .p,
                                            .{
                                                .children = &.{
                                                    _zx.txt("Deep content"),
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

pub fn CommentsWithAttributes(_: zx.ComponentContext) zx.Element {
    var _zx = @import("zx").x.init();
    return _zx.ele(
        .div,
        .{
            .children = &.{
                _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("After attribute comments"),
                        },
                    },
                ),
            },
        },
    );
}

pub fn MixedCommentsAndContent(_: zx.ComponentContext) zx.Element {
    var _zx = @import("zx").x.init();
    return _zx.ele(
        .ul,
        .{
            .children = &.{
                _zx.ele(
                    .li,
                    .{
                        .children = &.{
                            _zx.txt("Visible item 1"),
                        },
                    },
                ),
                _zx.ele(
                    .li,
                    .{
                        .children = &.{
                            _zx.txt("Visible item 2"),
                        },
                    },
                ),
                _zx.ele(
                    .li,
                    .{
                        .children = &.{
                            _zx.txt("Visible item 3"),
                        },
                    },
                ),
            },
        },
    );
}

pub fn CommentsWithZigCode(_: zx.ComponentContext) zx.Element {
    var _zx = @import("zx").x.init();
    return _zx.ele(
        .div,
        .{
            .children = &.{
                _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("After zig code comments"),
                        },
                    },
                ),
            },
        },
    );
}

pub fn CommentsOnlyComponent(_: zx.ComponentContext) zx.Element {
    var _zx = @import("zx").x.init();
    return _zx.ele(
        .div,
        .{
            .children = &.{},
        },
    );
}

pub fn CommentsBetweenSiblings(_: zx.ComponentContext) zx.Element {
    var _zx = @import("zx").x.init();
    return _zx.ele(
        .div,
        .{
            .children = &.{
                _zx.ele(
                    .header,
                    .{
                        .children = &.{
                            _zx.txt("Header"),
                        },
                    },
                ),
                _zx.ele(
                    .main,
                    .{
                        .children = &.{
                            _zx.txt("Main content"),
                        },
                    },
                ),
                _zx.ele(
                    .footer,
                    .{
                        .children = &.{
                            _zx.txt("Footer"),
                        },
                    },
                ),
            },
        },
    );
}

const zx = @import("zx");
