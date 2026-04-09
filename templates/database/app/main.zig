const std = @import("std");
const zx = @import("zx");
const Context = @import("Context.zig");

pub fn main() !void {
    const db_uri = std.process.getEnvVarOwned(zx.allocator, "DATABASE_URL") catch
        "postgresql://postgres:db_password@localhost:5432/ziex";

    var ctx: Context = .{ .db = try .init(zx.allocator, db_uri) };
    var app = try zx.App(*Context).init(zx.allocator, .{}, &ctx);
    defer app.deinit();

    try app.start();
}

pub const std_options = zx.std_options;
