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

        pub fn init(alloc: std.mem.Allocator, config: Config, app_ctx: H) !Self {
            const instance: Instance = switch (platform.role) {
                .client => {},
                .server => switch (platform.os) {
                    .wasi => {},
                    else => try server.Server(H).init(alloc, config, app_ctx),
                },
            };

            if (platform.role == .server and platform.os != .wasi) instance.info();
            return .{ .instance = instance };
        }

        pub fn deinit(self: *Self) void {
            if (platform.role == .server and platform.os != .wasi) self.instance.deinit();
            if (builtin.mode == .Debug) std.debug.assert(debug_allocator.deinit() == .ok);
        }

        pub fn start(self: Self) !void {
            switch (platform.role) {
                .client => try client.run(),
                .server => switch (platform.os) {
                    .wasi => try server_wasi.run(),
                    else => try self.instance.start(),
                },
            }
        }
    };
}

const NonNativeConfig = struct { server: struct { port: u16 = 0 } = .{} };
const Config = switch (platform.role) {
    .client => NonNativeConfig,
    .server => switch (platform.os) {
        .wasi => NonNativeConfig,
        else => server.ServerConfig,
    },
};

var debug_allocator: std.heap.DebugAllocator(.{}) = .{};
pub const allocator = switch (builtin.os.tag) {
    .wasi, .freestanding => std.heap.wasm_allocator,
    else => switch (builtin.mode) {
        .Debug => debug_allocator.allocator(),
        .ReleaseFast, .ReleaseSafe, .ReleaseSmall => std.heap.smp_allocator,
    },
};

const server = @import("runtime/server/Server.zig");
const server_wasi = @import("runtime/server/wasm/entrypoint.zig");
const client = @import("runtime/client/Client.zig").Client;
const platform = @import("platform.zig").platform;

const builtin = @import("builtin");
const std = @import("std");
