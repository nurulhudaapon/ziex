pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = zx.allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.cmp(Button, .{ .title = "Submit" }),
                _zx.cmp(Button, .{ .title = "Cancel" }),
                _zx.cmp(AsyncScore, .{ .index = 1, .label = "Score" }),
                _zx.cmp(AsyncScore, .{ .index = 2, .label = "Points" }),
                _zx.cmp(AsyncScore, .{ .index = 3, .label = "Rating" }),
            },
        },
    );
}

const ButtonProps = struct { title: []const u8 };
fn Button(allocator: zx.Allocator, props: ButtonProps) zx.Component {
    var _zx = zx.allocInit(allocator);
    return _zx.ele(
        .button,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.expr(props.title),
            },
        },
    );
}

const AsyncScoreProps = struct { index: u64, label: []const u8 };
fn AsyncScore(allocator: zx.Allocator, props: AsyncScoreProps) zx.Component {
    var _zx = zx.allocInit(allocator);
    return _zx.ele(
        .span,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.expr(props.label),
                _zx.txt(" #"),
                _zx.expr(props.index),
            },
        },
    );
}

const zx = @import("zx");
