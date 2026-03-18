pub fn Proxy(ctx: *zx.ProxyContext) !void {
    if (std.mem.eql(u8, ctx.request.pathname, "/old")) {
        ctx.response.redirect("/new", null);
        ctx.abort();
    } else {
        ctx.next();
    }
}

const std = @import("std");
const zx = @import("zx");
