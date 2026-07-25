const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

const cli = @import("cli/root.zig");
const context = @import("cli/shared/context.zig");
const AppContext = context.AppContext;

const use_debug_allocator = builtin.mode == .Debug and switch (builtin.os.tag) {
    .wasi, .freestanding => false,
    else => true,
};

pub fn main(init: std.process.Init) !void {
    var dbg: if (use_debug_allocator) std.heap.DebugAllocator(.{}) else void =
        if (use_debug_allocator) .init else {};
    defer if (comptime use_debug_allocator) std.debug.assert(dbg.deinit() == .ok);

    const allocator: std.mem.Allocator = if (comptime use_debug_allocator)
        dbg.allocator()
    else switch (builtin.os.tag) {
        .wasi, .freestanding => std.heap.wasm_allocator,
        else => std.heap.smp_allocator,
    };

    if (comptime builtin.os.tag == .windows) {
        _ = SetConsoleOutputCP(65001);
    }

    var stdout_writer = std.Io.File.stdout().writerStreaming(init.io, &.{});
    const stdout = &stdout_writer.interface;

    var stdin_buf: [4096]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(init.io, &stdin_buf);
    const stdin = &stdin_reader.interface;

    var app_ctx: AppContext = .{
        .io = init.io,
        .environ_map = init.environ_map,
    };

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const args = try init.minimal.args.toSlice(arena_state.allocator());

    try cli.run(stdout, stdin, allocator, args, &app_ctx);
    try stdout.flush();
}

extern "kernel32" fn SetConsoleOutputCP(wCodePageID: std.os.windows.UINT) callconv(.winapi) std.os.windows.BOOL;

pub const std_options = std.Options{
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .cli, .level = @enumFromInt(build_options.log_level) },
        .{ .scope = .devserver, .level = @enumFromInt(build_options.log_level) },
        .{ .scope = .builder, .level = @enumFromInt(build_options.log_level) },
    },
};
