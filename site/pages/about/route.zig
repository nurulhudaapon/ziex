pub fn Route(ctx: zx.RouteContext) !void {
    ctx.response.setBody("Hello, World!");
}

const zx = @import("zx");
