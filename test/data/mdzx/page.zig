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
    var _zx = @import("zx").x.allocInit(ctx.allocator);
    return _zx.ele(
        .div,
        .{
            .allocator = ctx.allocator,
            .children = &.{
                _zx.cmp(
                    Lightning,
                    .{ .name = "Lightning" },
                    .{ .class = "w-6 h-6 text-yellow-500" },
                ),
                _zx.ele(
                    .h1,
                    .{
                        .children = &.{
                            _zx.txt("1. Headers & Formatting"),
                        },
                    },
                ),
                _zx.ele(
                    .h1,
                    .{
                        .children = &.{
                            _zx.txt("H1 Header"),
                        },
                    },
                ),
                _zx.ele(
                    .h2,
                    .{
                        .children = &.{
                            _zx.txt("H2 Header"),
                        },
                    },
                ),
                _zx.ele(
                    .h3,
                    .{
                        .children = &.{
                            _zx.txt("H3 Header"),
                        },
                    },
                ),
                _zx.ele(
                    .h4,
                    .{
                        .children = &.{
                            _zx.txt("H4 Header"),
                        },
                    },
                ),
                _zx.ele(
                    .h5,
                    .{
                        .children = &.{
                            _zx.txt("H5 Header"),
                        },
                    },
                ),
                _zx.ele(
                    .h6,
                    .{
                        .children = &.{
                            _zx.txt("H6 Header"),
                        },
                    },
                ),
            },
        },
    );
}
