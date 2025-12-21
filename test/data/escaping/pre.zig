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
                            _zx.txt("                const data = "),
                            _zx.txt("                "),
                            _zx.txt("                Test   "),
                            _zx.txt("                        Test 2"),
                            _zx.txt("                "),
                            _zx.txt("                 name: \"test\" ;"),
                            _zx.txt("            "),
                        },
                    },
                ),
            },
        },
    );
}

const zx = @import("zx");
