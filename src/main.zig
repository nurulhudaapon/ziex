pub fn main(init: std.process.Init) !void {
    var dbg = std.heap.DebugAllocator(.{}).init;

    const allocator = switch (builtin.os.tag) {
        .wasi, .freestanding => std.heap.wasm_allocator,
        else => switch (builtin.mode) {
            .Debug => dbg.allocator(),
            .ReleaseFast, .ReleaseSafe, .ReleaseSmall => std.heap.smp_allocator,
        },
    };

    defer if (builtin.mode == .Debug) std.debug.assert(dbg.deinit() == .ok);

    // if (comptime (!build_options.exclude_lsp)) {
    //     var args = try init.minimal.args.iterateAllocator(allocator);
    //     defer args.deinit();

    //     _ = args.next();
    //     const subcmd = args.next();
    //     if (std.mem.eql(u8, subcmd orelse "", "lsp")) return try lsp.main();
    // }

    if (builtin.os.tag == .wasi) return try main_wasm(init);
    if (builtin.os.tag == .windows) _ = std.os.windows.kernel32.SetConsoleOutputCP(65001);

    var stdout_writer = std.Io.File.stdout().writerStreaming(init.io, &.{});
    var stdout = &stdout_writer.interface;

    var buf: [4096]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(init.io, &buf);
    const stdin = &stdin_reader.interface;

    const root = try cli.build(stdout, stdin, allocator);
    defer root.deinit();

    var app_ctx: AppContext = .{
        .io = init.io,
        .environ_map = init.environ_map,
    };

    try root.execute(.{ .process_args = init.minimal.args, .data = &app_ctx });

    try stdout.flush();
}

fn main_wasm(init: std.process.Init) !void {
    var dbg = std.heap.DebugAllocator(.{}).init;
    const allocator = dbg.allocator();
    var args = try init.minimal.args.iterateAllocator(allocator);
    defer args.deinit();

    // --- Sub Command --- //
    var is_transpile = false;
    var is_fmt = false;
    var is_lsp = false;

    _ = args.next(); // Drop executable name

    const sub_cmd = args.next() orelse return error.InvalidCommand;
    if (std.mem.eql(u8, sub_cmd, "transpile")) is_transpile = true;
    if (std.mem.eql(u8, sub_cmd, "fmt")) is_fmt = true;
    if (std.mem.eql(u8, sub_cmd, "lsp")) is_lsp = true;
    // if (is_lsp) return try lsp.main();

    var files = std.ArrayList([]const u8).empty;

    while (args.next()) |arg| {
        try files.append(allocator, arg);
    }

    var cwd = try std.Io.Dir.openDirAbsolute(init.io, "/codes", .{});
    defer cwd.close(init.io);

    // Transpile/Fmt file_path.zx and write with file_path.zig
    for (files.items) |file_path| {
        const zx_source = try cwd.readFileAlloc(init.io, file_path, allocator, .unlimited);
        const zx_sourcez = try allocator.dupeZ(u8, zx_source);

        const ast = try zx.Ast.parse(allocator, zx_sourcez, .{});
        const output = if (is_transpile) ast.zig_source else ast.zx_source;
        try std.Io.File.stdout().writeStreamingAll(init.io, output);
    }
}

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const zx = @import("zx");
const cli = @import("cli/root.zig");
const tui = @import("tui/main.zig");
const AppContext = @import("cli/shared/context.zig").AppContext;
// const lsp = if (build_options.exclude_lsp) void else @import("lsp/main.zig");

pub const std_options = std.Options{
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .cli, .level = if (builtin.mode == .Debug) .info else .info },
        .{ .scope = .devserver, .level = if (builtin.mode == .Debug) .info else .info },
        .{ .scope = .builder, .level = if (builtin.mode == .Debug) .info else .info },
    },
};
