pub fn PUT(ctx: zx.RouteContext) !void {
    try ctx.response.json(.{ .message = "HI" }, .{});
}

pub fn DELETE(ctx: zx.RouteContext) !void {
    ctx.response.cookies.delete("body", .{});
    ctx.response.cookies.delete("body-1", .{});
    try ctx.response.json(.{ .message = "Deleted" }, .{});
}

// Too much column width of codes
pub fn POST(ctx: zx.RouteContext) !void {
    const body = ctx.request.text() orelse "No body";
    ctx.response.cookies.set("body", body, .{});
    ctx.response.cookies.set("body-1", body, .{});
    try ctx.response.json(.{
        .message = "PST",
        .body = body,
    }, .{});
}

// Support multiple methods signature
// pub fn POST(req: zx.server.Request, res: zx.server.Response) !void {
//     const body = req.text() orelse "No body";
//     res.cookies.set("body", body, .{});
//     res.cookies.set("body-1", body, .{});
//     try res.json(.{
//         .message = "PST",
//         .body = body,
//     }, .{});
// }

// // Shortan cookie setter
// pub fn POST(res: zx.server.Response) !void {
//     res.cookie("id", "0");
//     try res.json(.{
//         .message = "PST",
//         .body = body,
//     }, .{});
// }

// // Add shorter high-level methods on ctx
// pub fn POST(res: zx.RouteContext) !void {
//     ctx.cookie("id", "0");
//     try ctx.res.json(.{
//         .message = "PST",
//         .body = body,
//     }, .{});
// }

const zx = @import("zx");
