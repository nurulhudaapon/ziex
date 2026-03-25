pub fn Page(allocator: zx.Allocator) zx.Component {
    const style: zx.Style = .{
        .color = .hex(0x0000ff),
    };
    var _zx = @import("zx").allocInit(allocator);
    return _zx.cmp(
        StyledCard,
        .{ .name = "StyledCard" },
        .{ .style = style, .children = _zx.ele(.fragment, .{ .children = &.{
            _zx.txt(" Hello Component "),
        } }) },
    );
}

const StyledCardProps = struct { style: zx.Style, children: zx.Component };
fn StyledCard(allocator: zx.Allocator, props: StyledCardProps) zx.Component {
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .div,
        .{
            .allocator = allocator,
            .attributes = _zx.attrs(.{
                _zx.attr("class", "card"),
                _zx.attr("style", props.style),
            }),
            .children = &.{
                _zx.expr(props.children),
            },
        },
    );
}

const zx = @import("zx");
