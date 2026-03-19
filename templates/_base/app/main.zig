const std = @import("std");
const zx = @import("zx");

pub fn main() !void {
    if (zx.platform == .browser) return zx.Client.run();
    if (zx.platform == .edge) return zx.Edge.run();

    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const app = try zx.Server(void).init(allocator, .{}, {});
    defer app.deinit();

    app.info();
    try app.start();
}

pub const std_options = zx.std_options;
