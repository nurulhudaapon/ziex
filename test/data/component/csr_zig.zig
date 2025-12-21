pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = zx.initWithAllocator(allocator);
    return _zx.zx(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.client(.{ .name = "CounterComponent", .path = "test/data/component/csr_zig.zig", .id = "zx-2676a2f99c98f8f91dd890d002af04ba" }, .{}),
            },
        },
    );
}

pub fn CounterComponent(allocator: zx.Allocator) zx.Component {
    var _zx = zx.initWithAllocator(allocator);
    return _zx.zx(
        .button,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.txt("Counter"),
            },
        },
    );
}

const zx = @import("zx");
