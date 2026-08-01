const std = @import("std");
const builtin = @import("builtin");

const App = @import("../App.zig");
const meta = @import("../../server/Server.zig");

pub const Std = @import("Server/Std.zig");
pub const Wasm = @import("Server/Wasm.zig");
pub const Httpz = @import("Server/Httpz.zig");

/// Wire a transport server instance into the shared App vtable.
pub fn bind(comptime ServerType: type, instance: *ServerType, alloc: std.mem.Allocator) !App {
    const Holder = struct {
        instance: *ServerType,
        alloc: std.mem.Allocator,

        const Self = @This();

        fn from(userdata: ?*anyopaque) *Self {
            return @ptrCast(@alignCast(userdata.?));
        }

        fn vtStart(userdata: ?*anyopaque) anyerror!void {
            const self = from(userdata);
            if (comptime builtin.optimize == .debug) {
                const stopFn = struct {
                    fn call(ctx: *anyopaque) void {
                        const s: *ServerType = @ptrCast(@alignCast(ctx));
                        s.stop();
                    }
                }.call;
                App.armSignal(self.instance, stopFn);
            }
            defer if (comptime builtin.optimize == .debug) App.disarmSignal();
            try self.instance.start();
        }

        fn vtStop(userdata: ?*anyopaque) void {
            from(userdata).instance.stop();
        }

        fn vtDeinit(userdata: ?*anyopaque) void {
            const self = from(userdata);
            const alloc_copy = self.alloc;
            self.instance.deinit();
            App.release(alloc_copy);
            alloc_copy.destroy(self);
            App.assertNoLeaks();
        }

        fn vtInfo(userdata: ?*anyopaque) void {
            from(userdata).instance.info();
        }

        const vtable = App.VTable{
            .start = &vtStart,
            .stop = &vtStop,
            .deinit = &vtDeinit,
            .info = &vtInfo,
        };
    };

    const holder = try alloc.create(Holder);
    holder.* = .{ .instance = instance, .alloc = alloc };

    if (App.mode != .@"export") instance.info();

    return .{ .userdata = @ptrCast(holder), .vtable = &Holder.vtable };
}
