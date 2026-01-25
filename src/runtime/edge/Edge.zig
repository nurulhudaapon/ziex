// TODO: freestanding handler to serve pages to the requested routes, this is to be used for edge runtime such as Cloudflare Workers, Deno Deploy, Vercel Edge Functions, etc.
pub fn Edge(comptime H: type) type {
    return struct {
        const Self = @This();

        app_ctx: H,

        pub fn fetch(allocator: std.mem.Allocator) ![]const u8 {
            if (zx.meta.routes[2]) |route| {
                if (route.page) |pg| {
                    const pg_ctx = zx.PageContext{
                        .request = .{
                            .url = "",
                            .method = .GET,
                            .pathname = "",
                            .headers = .{},
                            .arena = allocator,
                        },
                        .response = .{ .arena = allocator },
                        .allocator = allocator,
                        .arena = allocator,
                    };

                    const cmp = try pg(pg_ctx);
                    var aw = std.Io.Writer.Allocating.init(allocator);
                    defer aw.deinit();
                    try cmp.render(&aw.writer);

                    const cmp_str = aw.written();

                    return cmp_str;
                }
            }
        }
    };
}

const std = @import("std");
const builtin = @import("builtin");
const zx = @import("../../root.zig");
const module_config = @import("zx_info");
const Constant = @import("../../constant.zig");

const Allocator = std.mem.Allocator;
const Component = zx.Component;
const log = std.log.scoped(.app);
