const std = @import("std");
const zx = @import("zx");

pub fn main() !void {
    if (zx.platform.role == .client) return try zx.Client.run();
    if (zx.platform.isEdge()) return try zx.Edge.run();

    const allocator = std.heap.smp_allocator;
    const app = try zx.Server(void).init(allocator, .{}, {});
    defer app.deinit();

    app.info();
    try app.start();
}

pub const config = .{
    .csr = false,
};

pub const std_options = zx.std_options;
