const builtin = @import("builtin");
const std = @import("std");
const zx = @import("zx");

const config = zx.App.Config{ .meta = @import("meta.zig").meta, .server = .{ .port = 5588 } };
pub fn main() !void {
    if (builtin.os.tag == .freestanding) return;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const app = try zx.App.init(allocator, config);
    defer app.deinit();

    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();

    app.info();
    try app.start();
}

pub var client = zx.Client.init(
    if (builtin.os.tag == .freestanding) std.heap.wasm_allocator else std.heap.page_allocator,
    .{ .components = &@import(".zx/components.zig").components },
);

export fn mainClient() void {
    if (builtin.os.tag != .freestanding) return;
    client.info();
    client.renderAll();
}
