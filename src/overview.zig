pub fn QuickExample(allocator: zx.Allocator) zx.Component {
    const is_loading = true;
    const chars = "Hello, ZX Dev!";

    var _zx = zx.initWithAllocator(allocator);
return _zx.zx(
    .main,
    .{
        .allocator = allocator,
        .children = &.{
            _zx.zx(
                .section,
                .{
                    .children = &.{
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
                    },
                },
            ),
            _zx.zx(
                .section,
                .{
                    .children = &.{
                        blk: {
                            const __zx_children = _zx.getAllocator().alloc(zx.Component, chars.len) catch unreachable;
                            for (chars, 0..) |char, _zx_i| {
                                __zx_children[_zx_i] = _zx.zx(
                                    .span,
                                    .{
                                        .children = &.{
                                            _zx.fmt("{c}", .{char}),
                                        },
                                    },
                                );
                            }
                            break :blk __zx_children;
                        },
                    },
                },
            ),
            _zx.zx(
                .section,
                .{
                    .children = &.{
                        blk: {
                            const __zx_children = _zx.getAllocator().alloc(zx.Component, users.len) catch unreachable;
                            for (users, 0..) |user, _zx_i| {
                                __zx_children[_zx_i] = _zx.lazy(Profile, .{ .name = user.name,  .age = user.age,  .role = user.role });
                            }
                            break :blk __zx_children;
                        },
                    },
                },
            ),
        },
    },
);;
}

fn Profile(allocator: zx.Allocator, user: User) zx.Component {
    var _zx = zx.initWithAllocator(allocator);
return _zx.zx(
    .div,
    .{
        .allocator = allocator,
        .children = &.{
            _zx.zx(
                .h1,
                .{
                    .children = &.{
                        _zx.txt(user.name),
                    },
                },
            ),
            _zx.zx(
                .p,
                .{
                    .children = &.{
                        _zx.fmt("{d}", .{user.age}),
                    },
                },
            ),
            switch (user.role) {
                .admin => _zx.zx(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Admin"),
                        },
                    },
                ),
                .member => _zx.zx(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Member"),
                        },
                    },
                ),
            },
        },
    },
);;
}

const UserRole = enum { admin, member };
const User = struct { name: []const u8, age: u32, role: UserRole };

const users = [_]User{
    .{ .name = "John", .age = 20, .role = .admin },
    .{ .name = "Jane", .age = 21, .role = .member },
};

const zx = @import("zx");
