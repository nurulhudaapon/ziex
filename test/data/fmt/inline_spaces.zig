pub fn Collection(allocator: zx.Allocator, props: anytype) zx.Component {
    const cards = props.cards;
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .div,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                if (cards.len == 0) _zx.ele(
                    .fragment,
                    .{
                        .children = _zx.chs(.{
                            _zx.txt("No cards found with '"),
                            _zx.expr(props.name),
                            _zx.txt("' in their name"),
                            _zx.ele(
                                .br,
                                .{},
                            ),
                            _zx.txt("HINT: Try "),
                            _zx.ele(
                                .a,
                                .{
                                    .attributes = _zx.attrs(.{
                                        _zx.attr(@src(), "href", "/fetch/{props.name}"),
                                    }),
                                    .children = _zx.chs(.{
                                        _zx.txt("fetching them"),
                                    }),
                                },
                            ),
                        }),
                    },
                ) else _zx.ele(
                    .fragment,
                    .{
                        .children = _zx.chs(.{
                            _zx.expr(props.name),
                            _zx.expr(' '),
                            _zx.txt("in their name"),
                            _zx.ele(
                                .br,
                                .{},
                            ),
                            _zx.txt("HINT: Try"),
                            _zx.ele(
                                .a,
                                .{
                                    .attributes = _zx.attrs(.{
                                        _zx.attr(@src(), "href", "/fetch/{props.name}"),
                                    }),
                                    .children = _zx.chs(.{
                                        _zx.txt("fetching them"),
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
