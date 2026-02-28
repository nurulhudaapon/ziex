/// Test: CSR Zig component with props passed from server to client
pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.cmp(
                    Counter,
                    .{ .name = "Counter", .client = .{ .name = "Counter", .id = "c24eadf" } },
                    .{ .initial = 5, .label = "Main Counter" },
                ),
                _zx.cmp(
                    Counter,
                    .{ .name = "Counter", .client = .{ .name = "Counter", .id = "cd768fc" } },
                    .{ .initial = 10, .label = "Secondary" },
                ),
                _zx.cmp(
                    Counter,
                    .{ .name = "Counter", .client = .{ .name = "Counter", .id = "c9e599a" } },
                    .{ .initial = 0 },
                ),
            },
        },
    );
}

const CounterProps = struct { initial: i32 = 0, label: []const u8 = "Count" };
pub fn Counter(ctx: *zx.ComponentCtx(CounterProps)) zx.Component {
    var _zx = @import("zx").allocInit(ctx.allocator);
    return _zx.ele(
        .div,
        .{
            .allocator = ctx.allocator,
            .attributes = _zx.attrs(.{
                _zx.attr("class", "counter"),
            }),
            .children = &.{
                _zx.ele(
                    .span,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("class", "label"),
                        }),
                        .children = &.{
                            _zx.expr(ctx.props.label),
                        },
                    },
                ),
                _zx.ele(
                    .span,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("class", "value"),
                        }),
                        .children = &.{
                            _zx.expr(ctx.props.initial),
                        },
                    },
                ),
            },
        },
    );
}

const zx = @import("zx");
