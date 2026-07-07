const std = @import("std");
const builtin = @import("builtin");

const App = @import("../App.zig");
const impl = @import("../../server/Server.zig");

pub const Server = impl.Server;
pub const SerilizableAppMeta = impl.SerilizableAppMeta;

pub fn app(comptime H: type, instance: *Server(H), alloc: std.mem.Allocator) !App {
    const Holder = struct {
        instance: *Server(H),
        alloc: std.mem.Allocator,

        const Self = @This();

        fn from(userdata: ?*anyopaque) *Self {
            return @ptrCast(@alignCast(userdata.?));
        }

        fn vtStart(userdata: ?*anyopaque) anyerror!void {
            const self = from(userdata);
            // Only wire up graceful shutdown in debug builds.
            if (comptime builtin.mode == .Debug) {
                const stopFn = struct {
                    fn call(ctx: *anyopaque) void {
                        const s: *Server(H) = @ptrCast(@alignCast(ctx));
                        s.stop();
                    }
                }.call;
                App.armSignal(self.instance, stopFn);
            }
            defer if (comptime builtin.mode == .Debug) App.disarmSignal();
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
            // Leak check must run last, after the holder itself is freed.
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

    if (comptime impl.cli_cmd == .dev) instance.info();

    return .{ .userdata = @ptrCast(holder), .vtable = &Holder.vtable };
}
