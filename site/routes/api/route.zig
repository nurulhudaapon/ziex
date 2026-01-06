pub fn GET(ctx: zx.RouteContext) !void {
    try ctx.response.json(.{ .message = "Hello from GET!" }, .{});
}

pub fn POST(ctx: zx.RouteContext) !void {
    try ctx.response.json(.{ .message = "Created!" }, .{});
}

// Undefined standard methods will be handled by the catch-all Route handler
pub fn Route(ctx: zx.RouteContext) !void {
    try ctx.response.json(.{ .message = "Route!" }, .{});
}

const zx = @import("zx");
