pub fn PUT(ctx: zx.RouteContext) !void {
    try ctx.response.json(.{ .message = "HI" }, .{});
}

pub fn DELETE(ctx: zx.RouteContext) !void {
    ctx.response.deleteCookie("body", .{});
    ctx.response.deleteCookie("body-1", .{});
    try ctx.response.json(.{ .message = "Deleted" }, .{});
}

pub fn POST(ctx: zx.RouteContext) !void {
    const body = ctx.request.text() orelse "No body";
    ctx.response.setCookie("body", body, .{});
    ctx.response.setCookie("body-1", body, .{});
    try ctx.response.json(.{
        .message = "PST",
        .body = body,
    }, .{});
}

const zx = @import("zx");
