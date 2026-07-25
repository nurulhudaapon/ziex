pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                _zx.ele(
                    .div,
                    .{},
                ),
                _zx.ele(
                    .span,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr(@src(), "class", "spacer"),
                        }),
                    },
                ),
                _zx.ele(
                    .section,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr(@src(), "id", "empty-section"),
                        }),
                    },
                ),
            }),
        },
    );
}

const zx = @import("zx");
