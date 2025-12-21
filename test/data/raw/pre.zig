pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = zx.initWithAllocator(allocator);
    return _zx.zx(
        .section,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.zx(
                    .pre,
                    .{
                        .children = &.{
                            _zx.txt("\n                const data = \n                \n                Test   \n                        Test 2\n                \n                 name: \"test\" ;\n            "),
                        },
                    },
                ),
            },
        },
    );
}

const zx = @import("zx");
