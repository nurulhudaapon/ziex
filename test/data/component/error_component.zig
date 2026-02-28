/// Test: Components with error union return type (!Component)
pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.cmp(
                    Fallible,
                    .{ .name = "Fallible" },
                    .{ .success = true },
                ),
                _zx.cmp(
                    FallibleCtx,
                    .{ .name = "FallibleCtx" },
                    .{ .success = true },
                ),
            },
        },
    );
}

/// Error union with allocator signature
const FallibleProps = struct { success: bool };
pub fn Fallible(allocator: zx.Allocator, props: FallibleProps) !zx.Component {
    if (!props.success) return error.TestError;
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .div,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.txt("Success"),
            },
        },
    );
}

/// Error union with ComponentCtx signature
pub fn FallibleCtx(ctx: *zx.ComponentCtx(FallibleProps)) !zx.Component {
    if (!ctx.props.success) return error.TestError;
    var _zx = @import("zx").allocInit(ctx.allocator);
    return _zx.ele(
        .div,
        .{
            .allocator = ctx.allocator,
            .children = &.{
                _zx.txt("Ctx Success"),
            },
        },
    );
}

const zx = @import("zx");
