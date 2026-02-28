/// Test: Components with error union of optional return type (!?Component)
pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.cmp(
                    MaybeContent,
                    .{ .name = "MaybeContent" },
                    .{ .show = true },
                ),
                _zx.cmp(
                    MaybeContent,
                    .{ .name = "MaybeContent" },
                    .{ .show = false },
                ),
            },
        },
    );
}

/// Error union of optional - !?Component
const MaybeProps = struct { show: bool };
pub fn MaybeContent(ctx: *zx.ComponentCtx(MaybeProps)) !?zx.Component {
    if (!ctx.props.show) return null;
    var _zx = @import("zx").allocInit(ctx.allocator);
    return _zx.ele(
        .div,
        .{
            .allocator = ctx.allocator,
            .children = &.{
                _zx.txt("Shown Content"),
            },
        },
    );
}

const zx = @import("zx");
