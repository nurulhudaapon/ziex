const std = @import("std");
const zx = @import("zx");
const builtin = @import("builtin");

const config = zx.App.Config{ .server = .{} };

pub fn main() !void {
    if (zx.platform == .browser) return;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const app = try zx.Server(void).init(allocator, config, {});
    defer app.deinit();

    app.info();
    try app.start();
}

var client = zx.Client.init(zx.client_allocator, .{});

export fn mainClient() void {
    if (zx.platform != .browser) return;

    client.info();
    client.renderAll();
}

pub const std_options = zx.std_options;
