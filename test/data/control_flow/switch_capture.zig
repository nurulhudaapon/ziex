pub fn Page(allocator: zx.Allocator) zx.Component {
    const admin_user: User = .{ .admin = .{ .level = 5 } };
    const member_user: User = .{ .member = .{ .points = 150 } };

    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                switch (member_user) {
                    .admin => _zx.txt("Admin"),
                    .member => _zx.txt("Member"),
                },
                switch (admin_user) {
                    .admin => |admin| _zx.ele(
                        .p,
                        .{
                            .children = _zx.chs(.{
                                _zx.txt("Powerful - Level "),
                                _zx.expr(admin.level),
                            }),
                        },
                    ),
                    .member => |member| _zx.ele(
                        .p,
                        .{
                            .children = _zx.chs(.{
                                _zx.txt("Powerless - Points "),
                                _zx.expr(member.points),
                            }),
                        },
                    ),
                },
            }),
        },
    );
}

const User = union(enum) {
    admin: struct { level: u8 },
    member: struct { points: u16 },
};

const zx = @import("zx");
