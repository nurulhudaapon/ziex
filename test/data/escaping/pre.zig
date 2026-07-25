pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .section,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                _zx.ele(
                    .pre,
                    .{
                        .children = _zx.chs(.{
                            _zx.txt("                \n"),
                            _zx.expr(
                                \\const data = 
                                \\
                                \\ Test 
                                \\ Test 2
                                \\
                                \\ name: "test" ;
                                \\
                                \\
                            ),
                            _zx.txt("            "),
                        }),
                    },
                ),
            }),
        },
    );
}

const zx = @import("zx");
