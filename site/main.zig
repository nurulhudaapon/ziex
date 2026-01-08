const builtin = @import("builtin");
const std = @import("std");
const zx = @import("zx");

const config = zx.App.Config{ .meta = @import("meta.zig").meta, .server = .{ .port = 5588 } };

pub fn main() !void {
    if (zx.platform == .browser) return;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const app = try zx.App.init(allocator, config);
    defer app.deinit();

    app.info();
    try app.start();
}

var client = zx.Client.init(
    zx.client_allocator,
    .{ .components = &@import(".zx/components.zig").components },
);

export fn mainClient() void {
    if (zx.platform != .browser) return;
    client.info();
    client.renderAll();
}

pub const std_options = zx.std_options;

const ctx = zx.ComponentCtx(void);
