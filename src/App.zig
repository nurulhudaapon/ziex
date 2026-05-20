const std = @import("std");
const builtin = @import("builtin");
const platform = @import("platform.zig").platform;
const server = @import("runtime/server/Server.zig");
const server_wasi = @import("runtime/server/wasm/entrypoint.zig");
const client = @import("runtime/client/Client.zig").Client;

pub const Config = @import("AppConfig.zig");

var debug_allocator: std.heap.DebugAllocator(.{}) = .{};
pub const allocator = switch (builtin.os.tag) {
    .wasi, .freestanding => std.heap.wasm_allocator,
    else => switch (builtin.mode) {
        .Debug => debug_allocator.allocator(),
        .ReleaseFast, .ReleaseSafe, .ReleaseSmall => std.heap.smp_allocator,
    },
};

const Io = if (platform.os == .freestanding) void else std.Io;
pub fn io() Io {
    if (platform.os == .freestanding) return {};

    var threaded = std.Io.Threaded.init(allocator, .{});
    return threaded.io();
}

pub fn App(comptime H: type) type {
    return AppInstance(H);
}

fn AppInstance(comptime H: type) type {
    const Instance = switch (platform.role) {
        .client => void,
        .server => switch (platform.os) {
            .wasi => void,
            else => *server.Server(H),
        },
    };

    return struct {
        const Self = @This();

        instance: Instance,
        io: ?std.Io,

        pub fn init(process_io: anytype, alloc: std.mem.Allocator, config: Config, app_ctx: H) !Self {
            const instance: Instance = switch (platform.role) {
                .client => {},
                .server => switch (platform.os) {
                    .wasi => {},
                    else => try server.Server(H).init(
                        if (@TypeOf(process_io) == std.Io) process_io else return error.InvalidIo,
                        alloc,
                        config,
                        app_ctx,
                    ),
                },
            };

            if (platform.role == .server and platform.os != .wasi) instance.info();

            return .{
                .instance = instance,
                .io = if (@TypeOf(process_io) == std.Io) process_io else null,
            };
        }

        pub fn deinit(self: *Self) void {
            if (platform.role == .server and platform.os != .wasi) self.instance.deinit();
            if (builtin.mode == .Debug and platform.os != .freestanding)
                std.debug.assert(debug_allocator.deinit() == .ok);
        }

        pub fn start(self: Self) !void {
            switch (platform.role) {
                .client => try client.run(),
                .server => switch (platform.os) {
                    .wasi => try server_wasi.run(.{
                        .minimal = .{ .args = .{}, .environ = .{} },
                        .arena = undefined,
                        .gpa = allocator,
                        .io = self.io orelse undefined,
                        .environ_map = undefined,
                        .preopens = .empty,
                    }),
                    else => try self.instance.start(),
                },
            }
        }
    };
}
