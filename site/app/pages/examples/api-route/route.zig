const zx = @import("zx");

pub fn GET(ctx: zx.RouteContext) !void {
    try ctx.response.json(.{
        .method = "GET",
        .path = ctx.request.pathname,
    }, .{});
}

pub fn POST(ctx: zx.RouteContext) !void {
    const user = try ctx.request.json(struct { name: []const u8 }, .{});

    if (user == null) return try ctx.response.json(.{
        .message = "`name` field is required",
    }, .{});

    try ctx.response.json(.{
        .id = 1,
        .name = user.?.name,
        .status = "created",
    }, .{});
}
