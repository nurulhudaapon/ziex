pub fn QuickExample(allocator: zx.Allocator) zx.Component {
    const is_loading = true;
    const chars = "Hello, ZX Dev!";

    return var _zx = zx.initWithAllocator(allocator);
return _zx.zx(
    .main,
    .{
        .attributes = &.{
            .{ .name = "", .value = "" },
        },
        .children = &.{
            ,
            _zx.zx(
                .section,
                .{
                    .children = &.{
                        ,
                        if (is_loading) _zx.zx(
                            .h1,
                            .{
                                .children = &.{
                                    _zx.txt("Loading..."),
                                },
                            },
                        ) else _zx.zx(
                            .h1,
                            .{
                                .children = &.{
                                    _zx.txt("Loaded"),
                                },
                            },
                        ),
                        ,
                    },
                },
            ),
            ,
            ,
            _zx.zx(
                .section,
                .{
                    .children = &.{
                        ,
                        blk: {
                            const __zx_children = _zx.getAllocator().alloc(zx.Component, chars.len) catch unreachable;
                            for (chars, 0..) |char|, _zx_i| {
                                __zx_children[_zx_i] = _zx.zx(
                                    .span,
                                    .{
                                        .children = &.{
                                            _zx.txt([char:c]),
                                        },
                                    },
                                );
                            }
                            break :blk __zx_children;
                        },
                        ,
                    },
                },
            ),
            ,
            ,
            _zx.zx(
                .section,
                .{
                    .children = &.{
                        ,
                        blk: {
                            const __zx_children = _zx.getAllocator().alloc(zx.Component, users.len) catch unreachable;
                            for (users, 0..) |user|, _zx_i| {
                                __zx_children[_zx_i] = _zx.zx(
                                    .Profile,
                                    .{
                                        .attributes = &.{
                                            .{ .name = "", .value = "" },
                                            .{ .name = "", .value = "" },
                                            .{ .name = "", .value = "" },
                                        },
                                    },
                                );
                            }
                            break :blk __zx_children;
                        },
                        ,
                    },
                },
            ),
            ,
        },
    },
);
}

fn Profile(allocator: zx.Allocator, user: User) zx.Component {
    return var _zx = zx.initWithAllocator(allocator);
return _zx.zx(
    .div,
    .{
        .attributes = &.{
            .{ .name = "", .value = "" },
        },
        .children = &.{
            ,
            _zx.zx(
                .h1,
                .{
                    .children = &.{
                        _zx.txt(user.name),
                    },
                },
            ),
            ,
            _zx.zx(
                .p,
                .{
                    .children = &.{
                        _zx.txt([user.age:d]),
                    },
                },
            ),
            ,
            switch (user.role) {
                .admin => (<p>Admin</p>),
                .member => (<p>Member</p>),
            },
            ,
        },
    },
);
}

const UserRole = enum { admin, member };
const User = struct { name: []const u8, age: u32, role: UserRole };

const users = [_]User{
    .{ .name = "John", .age = 20, .role = .admin },
    .{ .name = "Jane", .age = 21, .role = .member },
};

const zx = @import("zx");