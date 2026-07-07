const App = @This();

const std = @import("std");
const builtin = @import("builtin");

const zx = @import("../../root.zig");
const Constant = @import("../../constant.zig");
const sig = @import("../../util/sig.zig");
const app_opts = @import("app_opts");
const platform = zx.platform;
const is_dev = std.mem.eql(u8, app_opts.cli_command, "dev");

pub const Config = @import("../../AppConfig.zig");

pub const Server = @import("App/Server.zig");
pub const Wasm = @import("App/Wasm.zig");
pub const Client = @import("App/Client.zig");

userdata: ?*anyopaque = null,
vtable: *const VTable = &failing_vtable,

pub const VTable = struct {
    start: *const fn (userdata: ?*anyopaque) anyerror!void,
    stop: *const fn (userdata: ?*anyopaque) void,
    deinit: *const fn (userdata: ?*anyopaque) void,
    info: *const fn (userdata: ?*anyopaque) void,
};

pub fn init(inita: zx.Init, process_io: anytype, alloc: std.mem.Allocator, config: Config, app_ctx: anytype) !App {
    const H = @TypeOf(app_ctx);
    const cfg = try resolveOptions(alloc, inita, config);

    switch (platform.role) {
        .client => return Client.app(),
        .server => switch (platform.os) {
            .wasi => return Wasm.app(inita),
            else => {
                const io_value = if (@TypeOf(process_io) == std.Io) process_io else return error.InvalidIo;
                const instance = try Server.Server(H).init(io_value, alloc, cfg, app_ctx);
                return Server.app(H, instance, alloc);
            },
        },
    }
}

pub fn start(self: App) !void {
    return self.vtable.start(self.userdata);
}

pub fn stop(self: App) void {
    self.vtable.stop(self.userdata);
}

pub fn deinit(self: *App) void {
    self.vtable.deinit(self.userdata);
}

pub fn info(self: App) void {
    self.vtable.info(self.userdata);
}

pub fn armSignal(instance: *anyopaque, on_stop: *const fn (ctx: *anyopaque) void) void {
    stop_ctx = instance;
    stop_fn = on_stop;
    sig.register(onSignal);
}

pub fn disarmSignal() void {
    sig.unregister();
    stop_ctx = null;
    stop_fn = null;
}

pub fn release(alloc: std.mem.Allocator) void {
    freeResolved(alloc);
    if (threaded_initialized) {
        threaded_instance.deinit();
        threaded_initialized = false;
    }
}

pub fn assertNoLeaks() void {
    if (builtin.mode == .Debug)
        std.debug.assert(debug_allocator.deinit() == .ok);
}

var stop_ctx: ?*anyopaque = null;
var stop_fn: ?*const fn (ctx: *anyopaque) void = null;

fn onSignal() void {
    if (stop_fn) |f| if (stop_ctx) |ctx| {
        if (!is_dev) std.debug.print("\nShutting down...\n", .{});
        f(ctx);
    };
}

var debug_allocator: std.heap.DebugAllocator(.{ .stack_trace_frames = 100 }) = .{};
pub const allocator = switch (builtin.os.tag) {
    .wasi, .freestanding => std.heap.wasm_allocator,
    else => switch (builtin.mode) {
        .Debug => debug_allocator.allocator(),
        .ReleaseFast, .ReleaseSafe, .ReleaseSmall => std.heap.smp_allocator,
    },
};

const Io = if (platform.os == .freestanding) void else std.Io;

var threaded_instance: std.Io.Threaded = undefined;
var threaded_initialized = false;

pub fn io() Io {
    if (platform.os == .freestanding) return {};

    if (!threaded_initialized) {
        threaded_instance = std.Io.Threaded.init(allocator, .{});
        threaded_initialized = true;
    }
    return threaded_instance.io();
}

var kv: zx.Kv = undefined;
var cache: zx.Cache = undefined;
var db: zx.Db = undefined;

var kv_fs: if (app_opts.feat_kv_server) zx.Kv.Fs else void = undefined;
var cache_fs: if (app_opts.feat_cache_server) zx.Kv.Fs else void = undefined;

const Resolved = struct {
    datadir: ?[]const u8 = null,
    staticdir: ?[]const u8 = null,
    db_url: ?[]const u8 = null,
    kv_subdir: ?[]const u8 = null,
    cache_subdir: ?[]const u8 = null,
};

var resolved: Resolved = .{};

fn resolveOptions(alloc: std.mem.Allocator, inita: zx.Init, config: Config) !Config {
    var cfg = config;

    const rootdir_env = envVar(alloc, inita, "ZIEX_ROOT_DIR");
    const datadir_env = envVar(alloc, inita, "ZIEX_DATA_DIR");
    const staticdir_env = envVar(alloc, inita, "ZIEX_STATIC_DIR");
    const port_env = envVar(alloc, inita, "PORT");

    defer if (rootdir_env) |s| alloc.free(s);
    defer if (datadir_env) |s| alloc.free(s);
    defer if (staticdir_env) |s| alloc.free(s);
    defer if (port_env) |s| alloc.free(s);

    const rootdir = rootdir_env orelse Constant.default_rootdir;
    const datadir = try std.fs.path.join(alloc, &.{ rootdir, datadir_env orelse Constant.default_datadir });
    const staticdir = try std.fs.path.join(alloc, &.{ rootdir, staticdir_env orelse Constant.default_staticdir });
    const port = if (port_env) |pe| std.fmt.parseInt(u16, pe, 10) catch return error.InvalidPort else cfg.server.port;

    cfg.datadir = datadir;
    cfg.staticdir = staticdir;
    cfg.server.port = port;

    switch (platform.os) {
        .freestanding, .wasi => |os| {
            // freestanding => client (browser wasm); wasi => server (server wasm).
            const wasm_kv_enabled = switch (os) {
                .wasi => app_opts.feat_kv_server,
                else => app_opts.feat_kv_client,
            };

            // Feature ==> zx.db (wasm backend, server-side only)
            if (comptime app_opts.feat_sqlite_server) {
                if (os == .wasi) zx.db = try zx.Db.Wasm.open(null, null, "default", .{});
            }

            // Feature ==> zx.kv (wasm backend)
            if (comptime wasm_kv_enabled) {
                var kv_wasm = zx.Kv.Wasm{};
                zx.kv = kv_wasm.kv();
            }

            return cfg;
        },
        else => {},
    }

    // Native target is always server-side from here on.

    // Feature ==> zx.kv (filesystem backend)
    if (comptime app_opts.feat_kv_server) {
        const kv_subdir = try std.fs.path.join(alloc, &.{ datadir, "kv" });
        kv_fs = .{ .io = inita.io, .subdir = kv_subdir };
        kv = kv_fs.kv();
        zx.kv = kv;
        resolved.kv_subdir = kv_subdir;
    }

    // Feature ==> zx.cache (filesystem backend)
    if (comptime app_opts.feat_cache_server) {
        const cache_subdir = try std.fs.path.join(alloc, &.{ datadir, "cache" });
        cache_fs = .{ .io = inita.io, .subdir = cache_subdir };
        const cache_kv: zx.Kv = cache_fs.kv();
        cache = try zx.Cache.init(inita.io, alloc, cache_kv, .{
            .max_size = cfg.cache.max_size,
        });
        zx.cache = cache;
        resolved.cache_subdir = cache_subdir;
    }

    // Feature ==> zx.db (sqlite backend)
    if (comptime app_opts.feat_sqlite_server) {
        const db_dir = try std.fs.path.join(alloc, &.{ datadir, "db", "default.db" });
        defer alloc.free(db_dir);
        const db_url = try std.fmt.allocPrint(alloc, "file:{s}", .{db_dir});
        zx.db = try zx.Db.Sqlite.open(alloc, inita.io, db_url, .{});
        resolved.db_url = db_url;
    }

    resolved.datadir = datadir;
    resolved.staticdir = staticdir;

    return cfg;
}

fn freeResolved(alloc: std.mem.Allocator) void {
    if (resolved.datadir == null) return;

    // Feature ==> zx.db (sqlite backend)
    if (comptime app_opts.feat_sqlite_server) {
        if (resolved.db_url) |s| {
            zx.db.deinit();
            alloc.free(s);
        }
    }

    // Feature ==> zx.cache
    if (comptime app_opts.feat_cache_server) {
        if (resolved.cache_subdir) |s| {
            zx.cache.deinit();
            alloc.free(s);
        }
    }

    // Feature ==> zx.kv
    if (comptime app_opts.feat_kv_server) {
        if (resolved.kv_subdir) |s| alloc.free(s);
    }

    if (resolved.staticdir) |s| alloc.free(s);
    if (resolved.datadir) |s| alloc.free(s);
    resolved = .{};
}

fn envVar(alloc: std.mem.Allocator, inita: zx.Init, name: []const u8) ?[]const u8 {
    if (platform.os == .freestanding or platform.os == .wasi) return null;
    const minimal: std.process.Init.Minimal = switch (@TypeOf(inita)) {
        std.process.Init.Minimal => inita,
        std.process.Init => inita.minimal,
        else => return null,
    };
    return minimal.environ.getAlloc(alloc, name) catch null;
}

fn failStart(_: ?*anyopaque) anyerror!void {
    return error.AppUnavailable;
}
fn failStop(_: ?*anyopaque) void {}
fn failDeinit(_: ?*anyopaque) void {}
fn failInfo(_: ?*anyopaque) void {}

pub const failing_vtable = VTable{
    .start = &failStart,
    .stop = &failStop,
    .deinit = &failDeinit,
    .info = &failInfo,
};

pub const Route = struct {
    path: []const u8,
    page: ?type = null,
    layout: ?type = null,
    notfound: ?type = null,
    @"error": ?type = null,
    route: ?type = null,
    proxy: ?type = null,
};
