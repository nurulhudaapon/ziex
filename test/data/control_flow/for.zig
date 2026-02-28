pub fn Page(allocator: zx.Allocator) zx.Component {
    const user_names = [_][]const u8{ "John", "Jane", "Jim", "Jill" };
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx_for_blk_0: {
                    const __zx_children_0 = _zx.getAlloc().alloc(@import("zx").Component, user_names.len) catch unreachable;
                    for (user_names, 0..) |name, _zx_i_0| {
                        __zx_children_0[_zx_i_0] = _zx.ele(
                            .p,
                            .{
                                .children = &.{
                                    _zx.expr(name),
                                },
                            },
                        );
                    }
                    break :_zx_for_blk_0 _zx.ele(.fragment, .{ .children = __zx_children_0 });
                },
            },
        },
    );
}

pub fn StructCapture(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx_for_blk_1: {
                    const __zx_children_1 = _zx.getAlloc().alloc(@import("zx").Component, users.len) catch unreachable;
                    for (users, 0..) |user, _zx_i_1| {
                        __zx_children_1[_zx_i_1] = _zx.ele(
                            .p,
                            .{
                                .children = &.{
                                    _zx.expr(user.name),
                                    _zx.txt(" - "),
                                    _zx.expr(user.age),
                                },
                            },
                        );
                    }
                    break :_zx_for_blk_1 _zx.ele(.fragment, .{ .children = __zx_children_1 });
                },
            },
        },
    );
}

pub fn StructExtraCapture(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx_for_blk_2: {
                    const __zx_children_2 = _zx.getAlloc().alloc(@import("zx").Component, users.len) catch unreachable;
                    for (users, 0.., 0..) |user, i, _zx_i_2| {
                        __zx_children_2[_zx_i_2] = _zx.ele(
                            .p,
                            .{
                                .children = &.{
                                    _zx.expr(i),
                                    _zx.txt(" - "),
                                    _zx.expr(user.name),
                                    _zx.txt(" - "),
                                    _zx.expr(user.age),
                                },
                            },
                        );
                    }
                    break :_zx_for_blk_2 _zx.ele(.fragment, .{ .children = __zx_children_2 });
                },
            },
        },
    );
}

pub fn StructComplexParam(allocator: zx.Allocator) zx.Component {
    const data = .{ .users = users };
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx_for_blk_3: {
                    const __zx_children_3 = _zx.getAlloc().alloc(@import("zx").Component, data.users.len) catch unreachable;
                    for (data.users, 0.., 0..) |u, i, _zx_i_3| {
                        __zx_children_3[_zx_i_3] = _zx.ele(
                            .p,
                            .{
                                .children = &.{
                                    _zx.expr(u),
                                    _zx.txt(" - "),
                                    _zx.expr(i),
                                    _zx.txt(" - "),
                                    _zx.expr(users[i].name),
                                    _zx.txt(" - "),
                                    _zx.expr(users[i].age),
                                },
                            },
                        );
                    }
                    break :_zx_for_blk_3 _zx.ele(.fragment, .{ .children = __zx_children_3 });
                },
                _zx_for_blk_4: {
                    const __zx_children_4 = _zx.getAlloc().alloc(@import("zx").Component, getUsers().len) catch unreachable;
                    for (getUsers(), 0.., 0..) |user, i, _zx_i_4| {
                        __zx_children_4[_zx_i_4] = _zx.ele(
                            .p,
                            .{
                                .children = &.{
                                    _zx.expr(i),
                                    _zx.txt(" - "),
                                    _zx.expr(user.name),
                                    _zx.txt(" - "),
                                    _zx.expr(user.age),
                                },
                            },
                        );
                    }
                    break :_zx_for_blk_4 _zx.ele(.fragment, .{ .children = __zx_children_4 });
                },
            },
        },
    );
}

fn getUsers() [users.len]User {
    return users;
}

pub fn StructCaptureToComponent(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx_for_blk_5: {
                    const __zx_children_5 = _zx.getAlloc().alloc(@import("zx").Component, users.len) catch unreachable;
                    for (users, 0..) |user, _zx_i_5| {
                        __zx_children_5[_zx_i_5] = _zx.cmp(
                            UserComponent,
                            .{ .name = "UserComponent" },
                            .{ .name = user.name, .age = user.age },
                        );
                    }
                    break :_zx_for_blk_5 _zx.ele(.fragment, .{ .children = __zx_children_5 });
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
    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .p,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.expr(props.name),
                _zx.txt(" - "),
                _zx.expr(props.age),
            },
        },
    );
}

const zx = @import("zx");
const std = @import("std");
