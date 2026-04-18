pub fn Page(allocator: zx.Allocator) zx.Component {
    const show_user_type = true;
    const user_type: UserType = .admin;
    var _zx = @import("zx").x.allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                if (show_user_type) _zx.ele(
                    .fragment,
                    .{
                        .children = &.{
                            (switch (user_type) {
                                .admin => _zx.ele(
                                    .p,
                                    .{
                                        .children = &.{
                                            _zx.txt("Admin"),
                                        },
                                    },
                                ),
                                .member => _zx.ele(
                                    .p,
                                    .{
                                        .children = &.{
                                            _zx.txt("Member"),
                                        },
                                    },
                                ),
                            }),
                        },
                    },
                ) else _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("User type hidden"),
                        },
                    },
                ),
            },
        },
    );
}

const zx = @import("zx");

const UserType = enum { admin, member };
