pub fn Page(allocator: zx.Allocator) zx.Component {
    const user_names = [_][]const u8{ "John", "Jane", "Jim", "Jill" };
    var _zx = zx.initWithAllocator(allocator);
    return _zx.zx(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                blk_0: {
                    const __zx_children_0 = _zx.getAllocator().alloc(zx.Component, user_names.len) catch unreachable;
                    for (user_names, 0..) |name, _zx_i_0| {
                        __zx_children_0[_zx_i_0] = _zx.zx(
                            .p,
                            .{
                                .children = &.{
                                    _zx.txt(name),
                                },
                            },
                        );
                    }
                    break :blk_0 _zx.zx(.fragment, .{ .children = __zx_children_0 });
                },
            },
        },
    );
}

pub fn StructCapture(allocator: zx.Allocator) zx.Component {
    var _zx = zx.initWithAllocator(allocator);
    return _zx.zx(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                blk_1: {
                    const __zx_children_1 = _zx.getAllocator().alloc(zx.Component, users.len) catch unreachable;
                    for (users, 0..) |user, _zx_i_1| {
                        __zx_children_1[_zx_i_1] = _zx.zx(
                            .p,
                            .{
                                .children = &.{
                                    _zx.txt(user.name),
                                    _zx.txt(" - "),
                                    _zx.fmt("{d}", .{user.age}),
                                },
                            },
                        );
                    }
                    break :blk_1 _zx.zx(.fragment, .{ .children = __zx_children_1 });
                },
            },
        },
    );
}

pub fn StructCaptureToComponent(allocator: zx.Allocator) zx.Component {
    var _zx = zx.initWithAllocator(allocator);
    return _zx.zx(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                blk_2: {
                    const __zx_children_2 = _zx.getAllocator().alloc(zx.Component, users.len) catch unreachable;
                    for (users, 0..) |user, _zx_i_2| {
                        __zx_children_2[_zx_i_2] = _zx.lazy(UserComponent, .{ .name = user.name, .age = user.age });
                    }
                    break :blk_2 _zx.zx(.fragment, .{ .children = __zx_children_2 });
                },
            },
        },
    );
}

const User = struct { name: []const u8, age: u32 };
const users = [_]User{
    .{ .name = "John", .age = 20 },
    .{ .name = "Jane", .age = 21 },
    .{ .name = "Jim", .age = 22 },
    .{ .name = "Jill", .age = 23 },
};

fn UserComponent(allocator: zx.Allocator, props: User) zx.Component {
    var _zx = zx.initWithAllocator(allocator);
    return _zx.zx(
        .p,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.txt(props.name),
                _zx.txt(" - "),
                _zx.fmt("{d}", .{props.age}),
            },
        },
    );
}

const zx = @import("zx");
const std = @import("std");
