pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = zx.initWithAllocator(allocator);
    return _zx.zx(
        .div,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.txt(" quote should be escaped "),
                _zx.zx(
                    .code,
                    .{
                        .children = &.{
                            _zx.txt("\"quote\""),
                        },
                    },
                ),
                _zx.zx(
                    .pre,
                    .{
                        .children = &.{
                            _zx.txt("\"quote\""),
                        },
                    },
                ),
            },
        },
    );
}

const zx = @import("zx");
