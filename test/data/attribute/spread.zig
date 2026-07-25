pub fn Page(allocator: zx.Allocator) zx.Component {
    const form_attrs = .{
        .@"data-name" = "hello",
        .class = "b-1 bold",
    };

    const input_props = .{
        .name = "email",
        .value = "test@example.com",
    };

    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .form,
        .{
            .allocator = allocator,
            .attributes = _zx.attrsM(.{
                _zx.attrSpr(form_attrs),
            }),
            .children = _zx.chs(.{
                _zx.cmp(
                    Input,
                    .{ .src = @src() },
                    .{ .name = "Input" },
                    input_props,
                ),
                _zx.cmp(
                    Input,
                    .{ .src = @src() },
                    .{ .name = "Input" },
                    _zx.propsM(input_props, .{ .extra = "override" }),
                ),
            }),
        },
    );
}

const InputProps = struct { value: []const u8, name: []const u8, extra: []const u8 = "" };
fn Input(ctx: *zx.ComponentCtx(InputProps)) zx.Component {
    var _zx = @import("zx").x.allocInit(ctx.allocator, .{ .src = @src() });
    return _zx.ele(
        .div,
        .{
            .allocator = ctx.allocator,
            .children = _zx.chs(.{
                _zx.ele(
                    .label,
                    .{
                        .children = _zx.chs(.{
                            _zx.expr(ctx.props.name),
                        }),
                    },
                ),
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrsM(.{
                            _zx.attr(@src(), "type", "text"),
                            _zx.attrSpr(ctx.props),
                        }),
                    },
                ),
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrsM(.{
                            _zx.attr(@src(), "extra", "override-by-spr"),
                            _zx.attrSpr(ctx.props),
                        }),
                    },
                ),
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrsM(.{
                            _zx.attr(@src(), "type", "text"),
                            _zx.attrSpr(ctx.props),
                            _zx.attr(@src(), "extra", "override-by-attr"),
                        }),
                    },
                ),
            }),
        },
    );
}

const zx = @import("zx");
