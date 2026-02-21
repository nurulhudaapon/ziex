pub fn Page(allocator: zx.Allocator) zx.Component {
    const u: User = .{ .member = .{ .points = 150 } };

    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                switch (u) {
                    .admin => _zx.txt("Admin"),
                    .member, .member2, .member3 => _zx.txt("Member"),
                    else => _zx.txt("Guest"),
                },
            },
        },
    );
}

const User = union(enum) {
    admin: struct { level: u8 },
    member: struct { points: u16 },
    member2: struct { points: u16 },
    member3: struct { points: u16 },
    guest: struct { points: u16 },
};

const zx = @import("zx");
