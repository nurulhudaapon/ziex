pub fn register(writer: *std.Io.Writer, reader: *std.Io.Reader, allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(writer, reader, allocator, .{
        .name = "serve",
        .description = "Run the server",
    }, serve);

    try cmd.addFlag(port_flag);
    try cmd.addFlag(flags.binpath_flag);

    var build_args_flag = flags.build_args;
    build_args_flag.default_value = .{ .String = "-Doptimize=ReleaseFast" };
    try cmd.addFlag(build_args_flag);

    return cmd;
}

const port_flag = zli.Flag{
    .name = "port",
    .shortcut = "p",
    .description = "Port to run the server on (0 means default or configured port)",
    .type = .Int,
    .default_value = .{ .Int = 0 },
    .hidden = true,
};

const DEFAULT_INSTALL_PREFIX = "zig-out";

fn serve(ctx: zli.CommandContext) !void {
    const app = AppContext.from(&ctx);
    const io = app.io;
    const port = ctx.flag("port", u32);

    var build_argv = std.ArrayList([]const u8).empty;
    defer build_argv.deinit(ctx.allocator);
    try build_argv.appendSlice(ctx.allocator, &.{ cli_options.zig_exe, "build" });
    try build_argv.appendSlice(ctx.allocator, &.{"-Dcli-command=serve"});

    var i_build_args = std.mem.splitSequence(u8, ctx.flag("build-args", []const u8), " ");
    while (i_build_args.next()) |arg| {
        const trimmed_arg = std.mem.trim(u8, arg, " ");
        if (std.mem.eql(u8, trimmed_arg, "")) continue;
        try build_argv.append(ctx.allocator, trimmed_arg);
    }

    var build_proc = try std.process.spawn(io, .{
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

    const binpath_flag = ctx.flag("binpath", []const u8);
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

const std = @import("std");
const zli = @import("zli");
const util = @import("shared/util.zig");
const flags = @import("shared/flag.zig");
const AppContext = @import("shared/context.zig").AppContext;
const cli_options = @import("cli_options");
const log = std.log.scoped(.cli);
