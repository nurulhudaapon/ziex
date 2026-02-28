pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").allocInit(allocator);
    return _zx.cmp(
        Button,
        "Button",
        .{},
        .{},
    );
}

pub fn Button(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .button,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.txt("Button"),
            },
        },
    );
}

const zx = @import("zx");
