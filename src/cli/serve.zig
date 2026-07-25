const std = @import("std");

const util = @import("shared/util.zig");
const context = @import("shared/context.zig");
const cli_args = @import("root.zig");

const CommandContext = context.CommandContext;
const log = std.log.scoped(.cli);
pub const command = cli_args.serve;

const DEFAULT_INSTALL_PREFIX = "zig-out";

pub fn run(ctx: CommandContext, args: anytype) !void {
    const app = ctx.app;
    const io = app.io;
    const port = args.port;

    var build_argv = std.ArrayList([]const u8).empty;
    defer build_argv.deinit(ctx.allocator);
    try build_argv.appendSlice(ctx.allocator, &.{ args.@"zig-path", "build" });
    try build_argv.appendSlice(ctx.allocator, &.{"-Dcli-command=serve"});

    var i_build_args = std.mem.splitSequence(u8, args.@"build-args", " ");
    while (i_build_args.next()) |arg| {
        const trimmed_arg = std.mem.trim(u8, arg, " ");
        if (std.mem.eql(u8, trimmed_arg, "")) continue;
        try build_argv.append(ctx.allocator, trimmed_arg);
    }

    var build_proc = try util.spawnZig(io, .{
        .argv = build_argv.items,
        .environ_map = app.environ_map,
    });
    switch (try build_proc.wait(io)) {
        .exited => |code| if (code != 0) {
            try ctx.writer.print("Failed to build the ZX executable for serve (exit {d})!\n", .{code});
            return;
        },
        else => {
            try ctx.writer.print("Failed to build the ZX executable for serve!\n", .{});
            return;
        },
    }

    const binpath_flag = args.binpath;
    const exe_path = util.resolveExePath(io, ctx.allocator, DEFAULT_INSTALL_PREFIX, binpath_flag) catch {
        try ctx.writer.print("Run \x1b[34mzig build\x1b[0m to build the ZX executable first!\n", .{});
        return;
    };
    defer ctx.allocator.free(exe_path);

    const environ_map = app.environ_map;
    try environ_map.put("ZIEX_ROOT_DIR", DEFAULT_INSTALL_PREFIX);

    const port_str = if (port != 0) try std.fmt.allocPrint(ctx.allocator, "{d}", .{port}) else null;
    defer if (port_str) |s| ctx.allocator.free(s);
    if (port_str) |s| try environ_map.put("PORT", s);

    log.debug("Spawning serve exe={s} rootdir={s}", .{ exe_path, DEFAULT_INSTALL_PREFIX });

    var app_child = try std.process.spawn(io, .{
        .argv = &.{ exe_path, "--cli-command", "serve" },
        .environ_map = environ_map,
        .stdout = .inherit,
        .stderr = .inherit,
    });

    const term = try app_child.wait(io);
    _ = term;
}
