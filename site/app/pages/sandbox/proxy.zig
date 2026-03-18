pub fn Proxy(ctx: *zx.ProxyContext) !void {
    ctx.state(UserState{ .count = 5 });
    ctx.next();
}

pub const UserState = struct {
    count: usize,
};

const std = @import("std");
const zx = @import("zx");
