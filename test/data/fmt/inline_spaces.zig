pub fn Collection(allocator: zx.Allocator, props: anytype) zx.Component {
    const cards = props.cards;
    var _zx = @import("zx").x.allocInit(allocator);
    return _zx.ele(
        .div,
        .{
            .allocator = allocator,
            .children = &.{
                if (cards.len == 0) _zx.ele(
                    .fragment,
                    .{
                        .children = &.{
                            _zx.txt(" No cards found with '"),
                            _zx.expr(props.name),
                            _zx.txt("' in their name"),
                            _zx.ele(
                                .br,
                                .{},
                            ),
                            _zx.txt(" HINT: Try "),
                            _zx.ele(
                                .a,
                                .{
                                    .attributes = _zx.attrs(.{
                                        _zx.attr("href", "/fetch/{props.name}"),
                                    }),
                                    .children = &.{
                                        _zx.txt("fetching them"),
                                    },
                                },
                            ),
                        },
                    },
                ) else _zx.ele(
                    .fragment,
                    .{
                        .children = &.{
                            _zx.expr(props.name),
                            _zx.expr(' '),
                            _zx.txt(" in their name"),
                            _zx.ele(
                                .br,
                                .{},
                            ),
                            _zx.txt(" HINT: Try"),
                            _zx.ele(
                                .a,
                                .{
                                    .attributes = _zx.attrs(.{
                                        _zx.attr("href", "/fetch/{props.name}"),
                                    }),
                                    .children = &.{
                                        _zx.txt("fetching them"),
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
