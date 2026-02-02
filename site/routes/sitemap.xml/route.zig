pub fn GET(ctx: zx.RouteContext) !void {
    var aw: std.Io.Writer.Allocating = .init(ctx.arena);
    var w = &aw.writer;
    const host = ctx.request.headers.get("host") orelse "ziex.dev";

    // Write XML header
    _ = try w.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    _ = try w.write("<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n");

    for (zx.routes) |route| {
        if (std.mem.indexOf(u8, route.path, ":") != null) continue;
        _ = try w.write("  <url>\n");
        _ = try w.write("    <loc>");
        const full_path = try std.fmt.allocPrint(ctx.arena, "https://{s}{s}", .{ host, route.path });
        _ = try w.write(full_path);
        _ = try w.write("</loc>\n");
        _ = try w.write("  </url>\n");
    }

    _ = try w.write("</urlset>\n");

    ctx.response.text(aw.written());
}

const options: zx.RouteOptions = .{
    .static = .{},
};

const zx = @import("zx");
const std = @import("std");
