pub fn PUT(ctx: zx.RouteContext) !void {
    ctx.response.text("Hello, World!");
}

const zx = @import("zx");
