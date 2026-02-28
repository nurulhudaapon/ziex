pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.cmp(
                    Button,
                    "Button",
                    .{},
                    .{ .title = "Click me" },
                ),
                _zx.cmp(
                    Alert,
                    "Alert",
                    .{},
                    .{ .message = "This is an alert", .level = "warning" },
                ),
                _zx.cmp(
                    Panel,
                    "Panel",
                    .{},
                    .{ .title = "Panel Title", .children = _zx.ele(.fragment, .{ .children = &.{
                        _zx.ele(
                            .p,
                            .{
                                .children = &.{
                                    _zx.txt("Panel content here"),
                                },
                            },
                        ),
                    } }) },
                ),
            },
        },
    );
}

/// Component using ComponentCtx with props (no children)
const ButtonProps = struct { title: []const u8 };
pub fn Button(ctx: *zx.ComponentCtx(ButtonProps)) zx.Component {
    var _zx = @import("zx").allocInit(ctx.allocator);
    return _zx.ele(
        .button,
        .{
            .allocator = ctx.allocator,
            .attributes = _zx.attrs(.{
                _zx.attr("class", "btn"),
            }),
            .children = &.{
                _zx.expr(ctx.props.title),
            },
        },
    );
}

/// Component with multiple props
const AlertProps = struct { message: []const u8, level: []const u8 };
fn Alert(ctx: *zx.ComponentCtx(AlertProps)) zx.Component {
    var _zx = @import("zx").allocInit(ctx.allocator);
    return _zx.ele(
        .div,
        .{
            .allocator = ctx.allocator,
            .attributes = _zx.attrs(.{
                _zx.attr("class", "alert"),
                _zx.attr("data-level", ctx.props.level),
            }),
            .children = &.{
                _zx.expr(ctx.props.message),
            },
        },
    );
}

/// Component with props AND children
const PanelProps = struct { title: []const u8 };
fn Panel(ctx: *zx.ComponentCtx(PanelProps)) zx.Component {
    var _zx = @import("zx").allocInit(ctx.allocator);
    return _zx.ele(
        .section,
        .{
            .allocator = ctx.allocator,
            .attributes = _zx.attrs(.{
                _zx.attr("class", "panel"),
            }),
            .children = &.{
                _zx.ele(
                    .h2,
                    .{
                        .children = &.{
                            _zx.expr(ctx.props.title),
                        },
                    },
                ),
                _zx.ele(
                    .div,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("class", "panel-content"),
                        }),
                        .children = &.{
                            _zx.expr(ctx.children),
                        },
                    },
                ),
            },
        },
    );
}

const zx = @import("zx");
