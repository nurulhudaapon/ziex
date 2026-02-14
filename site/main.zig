const builtin = @import("builtin");
const std = @import("std");
const zx = @import("zx");

const config = zx.Server(AppCtx).Config{ .server = .{ .port = 5588 } };

pub fn main() !void {
    if (zx.platform == .browser) return;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var app_ctx = AppCtx{ .port = 5588 };

    const server = try zx.Server(*AppCtx).init(allocator, config, &app_ctx);
    defer server.deinit();

    server.info();
    try server.start();
}

var client = zx.Client.init(zx.client_allocator, .{});

export fn mainClient() void {
    if (zx.platform != .browser) return;
    client.info();
    client.renderAll();
}

pub const std_options = zx.std_options;

pub const AppCtx = struct {
    port: u16,
};

pub const configs = .{
    // Example is on the SSR site beacuse the main site is statically generated and some of examples depends on the SSR.
    .example_url = if (builtin.mode == .Debug) "/examples" else "https://ssr.ziex.dev/examples",
    .main_site_url = if (builtin.mode == .Debug) "/" else zx.info.homepage,
};
