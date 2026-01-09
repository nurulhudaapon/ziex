pub fn Page(allocator: zx.Allocator) zx.Component {
    const user_type: UserType = .admin;
    const status: Status = .inactive;
    var _zx = zx.allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                switch (user_type) {
                    .admin => switch (status) {
                        .active => _zx.ele(
                            .p,
                            .{
                                .children = &.{
                                    _zx.txt("Active Admin"),
                                },
                            },
                        ),
                        .inactive => switch (status) {
                            .active => _zx.ele(
                                .p,
                                .{
                                    .children = &.{
                                        _zx.txt("Active Admin"),
                                    },
                                },
                            ),
                            .inactive => switch (status) {
                                .active => _zx.ele(
                                    .p,
                                    .{
                                        .children = &.{
                                            _zx.txt("Active Admin"),
                                        },
                                    },
                                ),
                                .inactive => switch (status) {
                                    .active => _zx.ele(
                                        .p,
                                        .{
                                            .children = &.{
                                                _zx.txt("Active Admin"),
                                            },
                                        },
                                    ),
                                    .inactive => _zx.ele(
                                        .p,
                                        .{
                                            .children = &.{
                                                _zx.txt("Inactive Admin"),
                                            },
                                        },
                                    ),
                                },
                            },
                        },
                    },
                    .member => switch (status) {
                        .active => switch (status) {
                            .active => switch (status) {
                                .active => _zx.ele(
                                    .p,
                                    .{
                                        .children = &.{
                                            _zx.txt("Active Admin"),
                                        },
                                    },
                                ),
                                .inactive => _zx.ele(
                                    .p,
                                    .{
                                        .children = &.{
                                            _zx.txt("Inactive Admin"),
                                        },
                                    },
                                ),
                            },
                            .inactive => _zx.ele(
                                .p,
                                .{
                                    .children = &.{
                                        _zx.txt("Inactive Admin"),
                                    },
                                },
                            ),
                        },
                        .inactive => switch (status) {
                            .active => _zx.ele(
                                .p,
                                .{
                                    .children = &.{
                                        _zx.txt("Active Admin"),
                                    },
                                },
                            ),
                            .inactive => _zx.ele(
                                .p,
                                .{
                                    .children = &.{
                                        _zx.txt("Inactive Admin"),
                                    },
                                },
                            ),
                        },
                    },
                },
            },
        },
    );
}

const zx = @import("zx");

const UserType = enum { admin, member };
const Status = enum { active, inactive };
