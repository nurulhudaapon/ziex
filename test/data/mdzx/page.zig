const zx = @import("zx");
const std = @import("std");
const Lightning = @import("site/pages/components/icons.zig").Lightning;
pub const meta = .{
    .title = "The Ultimate MDZX Test Suite",
    .version = "0.1.0",
    .tags = .{ "test", "markdown", "zig" },
    .draft = false,
};
pub const options: zx.PageOptions = .{};

pub fn _zx_md(ctx: *@import("zx").ComponentCtx(struct { children: @import("zx").Component })) @import("zx").Component {
    var _zx1 = @import("zx").x.allocInit(ctx.allocator, .{ .src = @src() });
    return _zx1.ele(
        .div,
        .{
            .allocator = ctx.allocator,
            .children = &.{
                _zx1.cmp(
                    Lightning,
                    .{ .src = @src() },
                    .{ .name = "Lightning" },
                    .{ .class = "w-6 h-6 text-yellow-500" },
                ),
                _zx1.ele(
                    .h1,
                    .{
                        .children = &.{
                            _zx1.txt("1. Headers & Formatting"),
                        },
                    },
                ),
                _zx1.ele(
                    .h1,
                    .{
                        .children = &.{
                            _zx1.txt("H1 Header"),
                        },
                    },
                ),
                _zx1.ele(
                    .h2,
                    .{
                        .children = &.{
                            _zx1.txt("H2 Header"),
                        },
                    },
                ),
                _zx1.ele(
                    .h3,
                    .{
                        .children = &.{
                            _zx1.txt("H3 Header"),
                        },
                    },
                ),
                _zx1.ele(
                    .h4,
                    .{
                        .children = &.{
                            _zx1.txt("H4 Header"),
                        },
                    },
                ),
                _zx1.ele(
                    .h5,
                    .{
                        .children = &.{
                            _zx1.txt("H5 Header"),
                        },
                    },
                ),
                _zx1.ele(
                    .h6,
                    .{
                        .children = &.{
                            _zx1.txt("H6 Header"),
                        },
                    },
                ),
            },
        },
    );
}
