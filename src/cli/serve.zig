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

fn serve(ctx: zli.CommandContext) !void {
    const app = AppContext.from(&ctx);
    const port = ctx.flag("port", u32);
    const port_str = try std.fmt.allocPrint(ctx.allocator, "{d}", .{port});
    defer ctx.allocator.free(port_str);
    const binpath = ctx.flag("binpath", []const u8);

    var build_args = std.ArrayList([]const u8).empty;
    defer build_args.deinit(ctx.allocator);
    try build_args.appendSlice(ctx.allocator, &.{ cli_options.zig_exe, "build", "serve" });

    var i_build_args = std.mem.splitSequence(u8, ctx.flag("build-args", []const u8), " ");
    while (i_build_args.next()) |arg| {
        const trimmed_arg = std.mem.trim(u8, arg, " ");
        if (std.mem.eql(u8, trimmed_arg, "")) continue;
        try build_args.append(ctx.allocator, trimmed_arg);
    }

    try build_args.append(ctx.allocator, "--");
    if (port != 0) try build_args.appendSlice(ctx.allocator, &.{ "--port", port_str });
    try build_args.appendSlice(ctx.allocator, &.{ "--cli-command", "serve" });

    var system = try std.process.spawn(app.io, .{ .argv = build_args.items });

    var program_meta = util.findprogram(app.io, ctx.allocator, binpath) catch |err| {
        log.debug("Error finding ZX executable! {any}\n", .{err});
        return;
    };
    defer util.freeBuildMeta(ctx.allocator, &program_meta);

    const term = try system.wait(app.io);
    _ = term;
}

const std = @import("std");
const zli = @import("zli");
const util = @import("shared/util.zig");
const flags = @import("shared/flag.zig");
const AppContext = @import("shared/context.zig").AppContext;
const cli_options = @import("cli_options");
const log = std.log.scoped(.cli);
