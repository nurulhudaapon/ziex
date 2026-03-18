pub fn GET(ctx: zx.RouteContext) !void {
    try ctx.response.json(.{ .name = "nurul" }, .{});
}

const options: zx.RouteOptions = .{
    .static = .{},
};

const zx = @import("zx");
const std = @import("std");
