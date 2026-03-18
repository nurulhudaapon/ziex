const builtin = @import("builtin");
const std = @import("std");
const zx = @import("zx");

const config = zx.Server(AppCtx).Config{ .server = .{ .port = 5588 } };

pub fn main() !void {
    if (zx.platform == .browser) return try zx.Client.run();
    if (zx.platform == .edge) return try zx.Edge.run();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var app_ctx = AppCtx{ .port = 5588 };

    const server = try zx.Server(*AppCtx).init(allocator, config, &app_ctx);
    defer server.deinit();

    server.info();
    try server.start();
}

pub const std_options = zx.std_options;

pub const AppCtx = struct {
    port: u16,
};

pub const configs = .{
    .main_site_url = if (builtin.mode == .Debug) "" else zx.info.homepage,
    // Some examples are on the SSR site beacuse the main site is statically generated and some of examples depends on the SSR.
    .ssr_url = if (builtin.mode == .Debug) "" else "https://ssr.ziex.dev",
    .ssg_url = if (builtin.mode == .Debug) "" else zx.info.homepage,
};
