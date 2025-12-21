pub fn Page(allocator: zx.Allocator) zx.Component {
    const max_count = 10;

    var _zx = zx.initWithAllocator(allocator);
    return _zx.zx(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.client(.{ .name = "CounterComponent", .path = "test/data/component/csr_react.tsx", .id = "zx-a59a5ab96d9fcd8a04c92ca4c34de61f" }, .{ .max_count = max_count }),
                _zx.client(.{ .name = "AnotherComponent", .path = "test/data/component/csr_react_multiple.tsx", .id = "zx-e9c79f618c4d5594d24a0aed36823b4c" }, .{}),
                _zx.client(.{ .name = "AnotherComponent", .path = "test/data/component/csr_react_multiple.tsx", .id = "zx-e9c79f618c4d5594d24a0aed36823b4c" }, .{}),
                _zx.client(.{ .name = "AnotherSameComponent", .path = "test/data/component/csr_react_multiple.tsx", .id = "zx-3401ac6fae86599b86f70018e2468df3" }, .{}),
            },
        },
    );
}

const zx = @import("zx");
// const CounterComponent = @jsImport("csr_react.tsx");
// const AnotherComponent = @jsImport("csr_react_multiple.tsx");
// const AnotherSameComponent = @jsImport("csr_react_multiple.tsx");
