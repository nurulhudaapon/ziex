pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.cmp(
                    Card,
                    .{ .name = "Card" },
                    .{ .title = "Welcome", .children = _zx.ele(.fragment, .{ .children = &.{
                        _zx.cmp(
                            Button,
                            .{ .name = "Button" },
                            .{ .label = "Click me" },
                        ),
                    } }) },
                ),
            },
        },
    );
}

const CardProps = struct { title: []const u8, children: zx.Component };
fn Card(allocator: zx.Allocator, props: CardProps) zx.Component {
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .div,
        .{
            .allocator = allocator,
            .attributes = _zx.attrs(.{
                _zx.attr("class", "card"),
            }),
            .children = &.{
                _zx.ele(
                    .h2,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("class", "card-header"),
                        }),
                        .children = &.{
                            _zx.expr(props.title),
                        },
                    },
                ),
                _zx.ele(
                    .div,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("class", "card-body"),
                        }),
                        .children = &.{
                            _zx.expr(props.children),
                        },
                    },
                ),
            },
        },
    );
}

const ButtonProps = struct { label: []const u8 };
fn Button(allocator: zx.Allocator, props: ButtonProps) zx.Component {
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .button,
        .{
            .allocator = allocator,
            .attributes = _zx.attrs(.{
                _zx.attr("class", "btn"),
            }),
            .children = &.{
                _zx.expr(props.label),
            },
        },
    );
}

const zx = @import("zx");
