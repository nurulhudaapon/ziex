pub fn Page(allocator: zx.Allocator) zx.Component {
    var iter = getIterator();

    var _zx = zx.allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx_whl_blk_0: {
                    var __zx_list_0 = @import("std").ArrayList(zx.Component).empty;
                    while (iter.next()) |item| {
                        __zx_list_0.append(_zx.getAlloc(), _zx.ele(
                            .p,
                            .{
                                .children = &.{
                                    _zx.expr(item),
                                },
                            },
                        )) catch unreachable;
                    } else |err| {
                        __zx_list_0.append(_zx.getAlloc(), _zx.ele(
                            .p,
                            .{
                                .children = &.{
                                    _zx.txt("Error: "),
                                    _zx.expr(@errorName(err)),
                                },
                            },
                        )) catch unreachable;
                    }
                    break :_zx_whl_blk_0 _zx.ele(.fragment, .{ .children = __zx_list_0.items });
                },
            },
        },
    );
}

fn getIterator() Iterator {
    return Iterator{ .items = &[_][]const u8{ "a", "b", "c" }, .index = 0 };
}

const Iterator = struct {
    items: []const []const u8,
    index: usize,

    fn next(self: *Iterator) error{Done}![]const u8 {
        if (self.index >= self.items.len) return error.Done;
        const item = self.items[self.index];
        self.index += 1;
        return item;
    }
};

const zx = @import("zx");
