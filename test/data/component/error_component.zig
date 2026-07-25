/// Test: Components with error union return type (!Component)
pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                _zx.cmp(
                    Fallible,
                    .{ .src = @src() },
                    .{ .name = "Fallible" },
                    .{ .success = true },
                ),
                _zx.cmp(
                    FallibleCtx,
                    .{ .src = @src() },
                    .{ .name = "FallibleCtx" },
                    .{ .success = true },
                ),
            }),
        },
    );
}

/// Error union with allocator signature
const FallibleProps = struct { success: bool };
pub fn Fallible(allocator: zx.Allocator, props: FallibleProps) !zx.Component {
    if (!props.success) return error.TestError;
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .div,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                _zx.txt("Success"),
            }),
        },
    );
}

/// Error union with ComponentCtx signature
pub fn FallibleCtx(ctx: *zx.ComponentCtx(FallibleProps)) !zx.Component {
    if (!ctx.props.success) return error.TestError;
    var _zx = @import("zx").x.allocInit(ctx.allocator, .{ .src = @src() });
    return _zx.ele(
        .div,
        .{
            .allocator = ctx.allocator,
            .children = _zx.chs(.{
                _zx.txt("Ctx Success"),
            }),
        },
    );
}

const zx = @import("zx");
