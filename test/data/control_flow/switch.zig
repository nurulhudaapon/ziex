pub fn Page(allocator: zx.Allocator) zx.Component {
    const user_type: UserType = .admin;
    var _zx = @import("zx").x.allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                switch (user_type) {
                    .admin => _zx.txt("Admin"),
                    .member => _zx.txt("Member"),
                },
                switch (user_type) {
                    .admin => _zx.txt("Admin"),
                    .member => _zx.txt("Member"),
                },
                switch (user_type) {
                    .admin => _zx.ele(
                        .p,
                        .{
                            .children = &.{
                                _zx.txt("Powerful"),
                            },
                        },
                    ),
                    .member => _zx.ele(
                        .p,
                        .{
                            .children = &.{
                                _zx.txt("Powerless"),
                            },
                        },
                    ),
                },
            },
        },
    );
}

const zx = @import("zx");

const UserType = enum { admin, member };
