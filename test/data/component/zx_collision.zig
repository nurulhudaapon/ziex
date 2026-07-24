pub fn Page(allocator: zx.Allocator) zx.Component {
    // User-declared `_zx` must not collide with the synthesized builder → `_zx1`.
    const _zx: []const u8 = "user";
    var _zx1 = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx1.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx1.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx1.expr(_zx),
                        },
                    },
                ),
            },
        },
    );
}

pub fn WithPrefix(allocator: zx.Allocator) zx.Component {
    // Any `_zx_*` binding also forces a numbered builder name → `_zx1`.
    const _zx_custom: usize = 1;
    _ = _zx_custom;
    var _zx1 = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx1.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx1.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx1.txt("ok"),
                        },
                    },
                ),
            },
        },
    );
}

pub fn ParameterCollision(allocator: zx.Allocator, _zx: []const u8) zx.Component {
    var _zx1 = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx1.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx1.expr(_zx),
            },
        },
    );
}

pub fn CaptureCollision(allocator: zx.Allocator) zx.Component {
    const values = [_][]const u8{ "a", "b" };
    var _zx1 = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx1.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx1_for_blk_0: {
                    const __zx1_children_0 = _zx1.getAlloc().alloc(@import("zx").Component, values.len) catch unreachable;
                    for (values, 0..) |_zx, _zx1_i_0| {
                        __zx1_children_0[_zx1_i_0] = _zx1.ele(
                            .span,
                            .{
                                .children = &.{
                                    _zx1.expr(_zx),
                                },
                            },
                        );
                    }
                    break :_zx1_for_blk_0 _zx1.ele(.fragment, .{ .children = __zx1_children_0 });
                },
            },
        },
    );
}

var _zx3 = 1;
const _zx2 = 2;
const __zx2_children_0 = 3;
const _zx_ele_blk_0 = 4;

// A module-scope ZX block must also avoid module declarations.
const module_component = _zx1_ele_blk_1: {
    var _zx1 = @import("zx").x.init(.{});
    break :_zx1_ele_blk_1 _zx1.ele(
        .aside,
        .{
            .children = &.{
                _zx1.txt("module"),
            },
        },
    );
};

pub fn NestedCollision(allocator: zx.Allocator) zx.Component {
    // Locals `_zx`/`_zx1` plus module `_zx2`/`_zx3` and helper-like names → `_zx4`.
    const _zx: []const u8 = "a";
    const _zx1: []const u8 = "b";
    const items = [_][]const u8{ "x", "y" };
    var _zx4 = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx4.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx4.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx4.expr(_zx),
                            _zx4.expr(_zx1),
                        },
                    },
                ),
                _zx4_for_blk_2: {
                    const __zx4_children_2 = _zx4.getAlloc().alloc(@import("zx").Component, items.len) catch unreachable;
                    for (items, 0..) |item, _zx4_i_2| {
                        __zx4_children_2[_zx4_i_2] = _zx4.ele(
                            .span,
                            .{
                                .children = &.{
                                    _zx4.expr(item),
                                },
                            },
                        );
                    }
                    break :_zx4_for_blk_2 _zx4.ele(.fragment, .{ .children = __zx4_children_2 });
                },
            },
        },
    );
}

pub fn ElementBlockCollision(allocator: zx.Allocator) zx.Component {
    const marker = _zx1_ele_blk_0: {
        break :_zx1_ele_blk_0 1;
    };
    _ = marker;

    // User/module block names occupy `_zx` through `_zx3`; the inline block uses `_zx4`.
    const child = _zx4_ele_blk_3: {
        var _zx4 = @import("zx").x.allocInit(allocator, .{ .src = @src() });
        break :_zx4_ele_blk_3 _zx4.ele(
            .section,
            .{
                .allocator = allocator,
                .children = &.{
                    _zx4.txt("inline"),
                },
            },
        );
    };
    return child;
}

pub fn ForHelperCollision(allocator: zx.Allocator) zx.Component {
    const _zx1_for_blk_0 = 1;
    const _zx1_i_0 = 2;
    const __zx1_children_0 = 3;
    _ = .{ _zx1_for_blk_0, _zx1_i_0, __zx1_children_0 };

    const items = [_][]const u8{ "x", "y" };
    var _zx4 = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx4.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx4_for_blk_4: {
                    const __zx4_children_4 = _zx4.getAlloc().alloc(@import("zx").Component, items.len) catch unreachable;
                    for (items, 0..) |item, _zx4_i_4| {
                        __zx4_children_4[_zx4_i_4] = _zx4.ele(
                            .span,
                            .{
                                .children = &.{
                                    _zx4.expr(item),
                                },
                            },
                        );
                    }
                    break :_zx4_for_blk_4 _zx4.ele(.fragment, .{ .children = __zx4_children_4 });
                },
            },
        },
    );
}

pub fn WhileHelperCollision(allocator: zx.Allocator) zx.Component {
    const _zx1_whl_blk_0 = 1;
    const __zx1_list_0 = 2;
    _ = .{ _zx1_whl_blk_0, __zx1_list_0 };

    var i: usize = 0;
    var _zx4 = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx4.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx4_whl_blk_5: {
                    var __zx4_list_5 = @import("std").ArrayList(@import("zx").Component).empty;
                    while (i < 2) : (i += 1) {
                        __zx4_list_5.append(_zx4.getAlloc(), _zx4.ele(
                            .span,
                            .{
                                .children = &.{
                                    _zx4.expr(i),
                                },
                            },
                        )) catch unreachable;
                    }
                    break :_zx4_whl_blk_5 _zx4.ele(.fragment, .{ .children = __zx4_list_5.items });
                },
            },
        },
    );
}

const zx = @import("zx");
