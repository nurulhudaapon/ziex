const std = @import("std");
const zx = @import("zx");
const Context = @import("Context.zig");

pub fn main() !void {
    if (zx.platform == .browser) return zx.Client.run();
    if (zx.platform == .edge) return zx.Edge.run();

    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const db_uri = std.process.getEnvVarOwned(allocator, "DATABASE_URL") catch
        "postgresql://postgres:db_password@localhost:5432/ziex";

    var ctx: Context = .{ .db = try .init(allocator, db_uri) };
    const app = try zx.Server(*Context).init(allocator, .{}, &ctx);
    defer app.deinit();

    app.info();
    try app.start();
}

pub const std_options = zx.std_options;
