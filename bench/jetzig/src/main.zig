const std = @import("std");
const builtin = @import("builtin");

const jetzig = @import("jetzig");
const zmd = @import("zmd");

pub const routes = @import("routes");
pub const static = @import("static");

/// Match Ziex/httpz ServerConfig
pub const jetzig_options = struct {
    pub const worker_count: u16 = 1;
    pub const thread_count: ?u16 = null;
    pub const buffer_size: usize = 32_768;
    pub const max_connections: u16 = 8_192;
    pub const arena_size: usize = 8192;
};

pub fn init(app: *jetzig.App) !void {
    _ = app;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = if (builtin.mode == .Debug) gpa.allocator() else std.heap.c_allocator;
    defer if (builtin.mode == .Debug) std.debug.assert(gpa.deinit() == .ok);

    var app = try jetzig.init(allocator);
    defer app.deinit();

    try app.start(routes, .{});
}

pub const std_options: std.Options = .{
    .log_level = .err,
};
