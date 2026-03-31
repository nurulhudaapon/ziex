pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.ele(
                    .h1,
                    .{
                        .children = &.{
                            _zx.txt("Welcome to the site!"),
                        },
                    },
                ),
            },
        },
    );
}

const zx = @import("zx");
