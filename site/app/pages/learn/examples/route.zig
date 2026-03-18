const zx = @import("zx");

pub fn GET(ctx: zx.RouteContext) !void {
    try ctx.response.json(.{ .message = "Hello World!" }, .{});
}
