pub fn Page(allocator: zx.Allocator) zx.Component {
    const max_count = 10;

    var _zx = @import("zx").x.allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.client(.{ .name = "CounterComponent", .path = "test/data/component/react.tsx", .id = "cc92487" }, .{ .max_count = max_count }),
                _zx.client(.{ .name = "AnotherComponent", .path = "test/data/component/csr_react_multiple.tsx", .id = "c36ddbb" }, .{}),
                _zx.client(.{ .name = "AnotherComponent", .path = "test/data/component/csr_react_multiple.tsx", .id = "c77b548" }, .{}),
                _zx.client(.{ .name = "AnotherSameComponent", .path = "test/data/component/csr_react_multiple.tsx", .id = "c005539" }, .{}),
            },
        },
    );
}

const zx = @import("zx");
// const CounterComponent = @jsImport("react.tsx");
// const AnotherComponent = @jsImport("csr_react_multiple.tsx");
// const AnotherSameComponent = @jsImport("csr_react_multiple.tsx");
