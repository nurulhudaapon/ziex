pub fn Page(allocator: zx.Allocator) zx.Component {
    const max_count = 10;

    var _zx = zx.initWithAllocator(allocator);
    return _zx.zx(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.client(.{ .name = "CounterComponent", .path = "test/data/component/csr_react.tsx", .id = "zx-a59a5ab96d9fcd8a04c92ca4c34de61f" }, .{ .max_count = max_count }),
            },
        },
    );
}

const zx = @import("zx");
// const CounterComponent = @jsImport("csr_react.tsx");
