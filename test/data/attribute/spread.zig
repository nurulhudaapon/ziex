pub fn Page(allocator: zx.Allocator) zx.Component {
    const form_attrs = .{
        .@"data-name" = "hello",
        .class = "b-1 bold",
    };

    const input_props = .{
        .name = "email",
        .value = "test@example.com",
    };

    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .form,
        .{
            .allocator = allocator,
            .attributes = _zx.attrsM(.{
                _zx.attrSpr(form_attrs),
            }),
            .children = &.{
                _zx.cmp(
                    Input,
                    .{ .name = "Input" },
                    input_props,
                ),
                _zx.cmp(
                    Input,
                    .{ .name = "Input" },
                    _zx.propsM(input_props, .{ .extra = "override" }),
                ),
            },
        },
    );
}

const InputProps = struct { value: []const u8, name: []const u8, extra: []const u8 = "" };
fn Input(ctx: *zx.ComponentCtx(InputProps)) zx.Component {
    var _zx = @import("zx").init();
    return _zx.ele(
        .div,
        .{
            .children = &.{
                _zx.ele(
                    .label,
                    .{
                        .children = &.{
                            _zx.expr(ctx.props.name),
                        },
                    },
                ),
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrsM(.{
                            _zx.attr("type", "text"),
                            _zx.attrSpr(ctx.props),
                        }),
                    },
                ),
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrsM(.{
                            _zx.attr("extra", "override-by-spr"),
                            _zx.attrSpr(ctx.props),
                        }),
                    },
                ),
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrsM(.{
                            _zx.attr("type", "text"),
                            _zx.attrSpr(ctx.props),
                            _zx.attr("extra", "override-by-attr"),
                        }),
                    },
                ),
            },
        },
    );
}

const zx = @import("zx");
