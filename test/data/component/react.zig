pub fn Page(allocator: zx.Allocator) zx.Component {
    const max_count = 10;

    var _zx = @import("zx").x.allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.client(.{ .name = "CounterComponent", .path = "test/data/component/react.tsx", .id = "cc92487" }, .{ .max_count = max_count }),
            },
        },
    );
}

const zx = @import("zx");
// const CounterComponent = @jsImport("react.tsx");
