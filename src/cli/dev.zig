const std = @import("std");
const zli = @import("zli");
const zx = @import("zx");
const cli_options = @import("cli_options");
const builtin = @import("builtin");

const util = @import("shared/util.zig");
const flag = @import("shared/flag.zig");
const Builder = @import("dev/Builder.zig");
const tui = @import("../tui/main.zig");
const Diagnostics = @import("dev/Diagnostics.zig");
const DevServer = @import("dev/DevServer.zig");

const Colors = tui.Colors;
const log = std.log.scoped(.cli);

pub fn register(writer: *std.Io.Writer, reader: *std.Io.Reader, allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(writer, reader, allocator, .{
        .name = "dev",
        .description = "Start the app in development mode with rebuild on change",
    }, dev);

    try cmd.addFlag(flag.binpath_flag);
    try cmd.addFlag(flag.build_args);
    try cmd.addFlag(.{
        .name = "port",
        .description = "Port to run the server on (0 means default or configured port)",
        .type = .Int,
        .default_value = .{ .Int = 0 },
        .hidden = true,
    });
    try cmd.addFlag(.{
        .name = "tui-progress",
        .description = "Show full build progress output from zig build",
        .type = .Bool,
        .default_value = .{ .Bool = true },
    });
    try cmd.addFlag(.{
        .name = "tui-underline",
        .description = "Show underlined status messages",
        .type = .Bool,
        .default_value = .{ .Bool = true },
    });
    try cmd.addFlag(.{
        .name = "tui-spinner",
        .description = "Show spinner for status messages",
        .type = .Bool,
        .default_value = .{ .Bool = false },
    });
    try cmd.addFlag(.{
        .name = "tui-clear",
        .description = "Clear the terminal before every restart",
        .type = .Bool,
        .default_value = .{ .Bool = false },
    });

    return cmd;
}

const BIN_DIR = "zig-out/bin";

fn dev(ctx: zli.CommandContext) !void {
    const allocator = ctx.allocator;
    const binpath = ctx.flag("binpath", []const u8);
    const port = ctx.flag("port", u32);
    const port_str = try std.fmt.allocPrint(ctx.allocator, "{d}", .{port});
    defer ctx.allocator.free(port_str);
    const build_args_str = ctx.flag("build-args", []const u8);
    const use_spinner = ctx.flag("tui-spinner", bool);
    const clear_on_restart = ctx.flag("tui-clear", bool);
    var build_args = std.mem.splitSequence(u8, build_args_str, " ");

    var build_args_array = std.ArrayList([]const u8).empty;
    var initial_build_args_array = std.ArrayList([]const u8).empty;
    defer initial_build_args_array.deinit(allocator);

    try build_args_array.appendSlice(allocator, &.{ cli_options.zig_exe, "build", "--watch", "--verbose", "--summary", "all", "--color", "off" });
    try initial_build_args_array.appendSlice(allocator, &.{ cli_options.zig_exe, "build" });

    while (build_args.next()) |arg| {
        const trimmed_arg = std.mem.trim(u8, arg, " ");
        if (std.mem.eql(u8, trimmed_arg, "")) continue;
        try build_args_array.appendSlice(allocator, &.{trimmed_arg});
        try initial_build_args_array.appendSlice(allocator, &.{trimmed_arg});
    }

    // Force color output even when piped (for error display)
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    var initial_build = std.process.Child.init(initial_build_args_array.items, allocator);
    _ = initial_build.spawnAndWait() catch {};

    // Spin up the dev proxy: it owns the user-facing port for the entire session
    const outer_port: u16 = if (port != 0) @intCast(port) else 3000;
    const inner_port = DevServer.findFreePort() catch outer_port + 1;
    const inner_port_str = try std.fmt.allocPrint(allocator, "{d}", .{inner_port});
    defer allocator.free(inner_port_str);
    const outer_port_str = try std.fmt.allocPrint(allocator, "{d}", .{outer_port});
    defer allocator.free(outer_port_str);

    try env_map.put("ZIEX_INNER_PORT", inner_port_str);
    try env_map.put("ZIEX_OUTER_PORT", outer_port_str);

    log.debug("starting devserver, inner: {d}: outer: {d}", .{ inner_port, outer_port });
    var dev_server = DevServer.init(.{
        .gpa = allocator,
        .address = try std.net.Address.parseIp("0.0.0.0", outer_port),
        .inner_port = inner_port,
    });
    defer dev_server.deinit();
    dev_server.start() catch |err| {
        try ctx.writer.print("Failed to start dev proxy: {any}\n", .{err});
        return;
    };

    var builder = std.process.Child.init(build_args_array.items, allocator);
    builder.stderr_behavior = .Pipe;
    builder.stdout_behavior = .Pipe;

    try builder.spawn();
    defer _ = builder.kill() catch unreachable;

    var build_state = Builder.BuildState.init(allocator, null, 0);
    defer build_state.deinit();

    var runner: ?std.process.Child = null;
    var runner_output: ?util.ChildOutput = null;
    var program_path: ?[]const u8 = null;

    defer {
        if (runner) |*r| {
            _ = r.kill() catch {};
            _ = r.wait() catch {};
        }
        if (runner_output) |*o| o.deinit();
        if (program_path) |p| allocator.free(p);
    }

    // Tracks wall-clock time from "change detected" to runner restart complete.
    var rebuild_timer: ?std.time.Timer = null;
    var rebuilding_shown = false;
    var is_first_run = true;
    var last_was_no_change = false;
    var last_error_formatted: ?[]const u8 = null;
    defer if (last_error_formatted) |prev| allocator.free(prev);

    var stderr_file = builder.stderr.?;
    var raw_buf: [8192]u8 = undefined;
    var streaming_reader = stderr_file.readerStreaming(&raw_buf);
    const io_reader = &streaming_reader.interface;
    var line_writer = std.Io.Writer.Allocating.init(allocator);
    defer line_writer.deinit();

    while (io_reader.streamDelimiter(&line_writer.writer, '\n')) |_| {
        const line = line_writer.written();
        _ = io_reader.takeByte() catch break;

        if (try build_state.processLine(line)) |event| {
            switch (event) {
                .change_detected => {
                    last_was_no_change = false;
                    if (last_error_formatted) |prev| {
                        allocator.free(prev);
                        last_error_formatted = null;
                    }
                    rebuild_timer = std.time.Timer.start() catch null;
                    dev_server.notifyBuilding();
                    if (use_spinner) {
                        if (rebuilding_shown) {
                            var spinner = ctx.spinner;
                            try spinner.updateMessage("{s}Rebuilding...{s}", .{ Colors.cyan, Colors.reset });
                        } else {
                            try ctx.writer.print("\n", .{});
                            var spinner = ctx.spinner;
                            spinner.updateStyle(.{ .frames = zli.Spinner.SpinnerStyles.dots2, .refresh_rate_ms = 80 });
                            try spinner.start("{s}Rebuilding...{s}", .{ Colors.cyan, Colors.reset });
                        }
                    } else {
                        const prefix = if (rebuilding_shown) "\r" else "\n";
                        try ctx.writer.print("{s}{s}↺ {s}Rebuilding...{s}\x1b[K", .{ prefix, Colors.cyan, Colors.bold, Colors.reset });
                    }
                    rebuilding_shown = true;
                },
                .errors => |result_val| {
                    last_was_no_change = false;
                    var build_result = result_val;
                    defer build_result.deinit();

                    Diagnostics.remap(allocator, build_result.diagnostics);
                    const identical_check = try Builder.formatDiagnostics(allocator, build_result.diagnostics);
                    defer allocator.free(identical_check);

                    const is_identical = if (last_error_formatted) |prev|
                        std.mem.eql(u8, identical_check, prev)
                    else
                        false;

                    if (!is_identical) {
                        if (last_error_formatted) |prev| allocator.free(prev);
                        last_error_formatted = try allocator.dupe(u8, identical_check);
                    }

                    const formatted_oxlint = try Diagnostics.formatOxlint(allocator, build_result.diagnostics);
                    defer allocator.free(formatted_oxlint);

                    if (use_spinner and rebuilding_shown) {
                        var spinner = ctx.spinner;
                        if (rebuild_timer) |_| {
                            try spinner.fail("{s}Error building{s}", .{ Colors.red, Colors.reset });
                        }
                        rebuild_timer = null;
                    } else if (rebuild_timer) |_| {
                        try ctx.writer.print("\r{s}✖ {s}Error building{s}\x1b[K\n", .{ Colors.red, Colors.bold, Colors.reset });
                        rebuild_timer = null;
                    }

                    if (!is_identical) {
                        try ctx.writer.writeAll(formatted_oxlint);
                    }

                    const error_json = Diagnostics.toJson(allocator, build_result.diagnostics) catch null;
                    if (error_json) |json| {
                        defer allocator.free(json);
                        if (build_result.diagnostics.len > 0) dev_server.notifyRawJson(json);
                    } else {
                        dev_server.notifyError(formatted_oxlint);
                    }
                    rebuilding_shown = false;
                },
                .resolved => {
                    last_was_no_change = false;
                    try ctx.writer.print("{s} ✓ {s}All build errors have been resolved!{s}\n", .{ Colors.green, Colors.bold, Colors.reset });
                    dev_server.notifyClear();
                },
                .build_complete_no_change => |_| {
                    if (rebuilding_shown) {
                        const dim = "\x1b[2m";
                        if (use_spinner) {
                            ctx.spinner.stop();
                        }
                        if (last_was_no_change) {
                            try ctx.writer.print("\x1b[1A\r{s}✓ No changes{s}\x1b[K\n", .{ dim, Colors.reset });
                        } else {
                            try ctx.writer.print("\r{s}✓ No changes{s}\x1b[K\n", .{ dim, Colors.reset });
                        }
                    }
                    dev_server.notifyClear();
                    rebuild_timer = null;
                    rebuilding_shown = false;
                    last_was_no_change = true;
                },
                .should_restart => |build_duration_ms| {
                    last_was_no_change = false;
                    log.debug("Processing startup/restart request...", .{});

                    const wall_build_ms: u64 = if (rebuild_timer) |*t| t.read() / std.time.ns_per_ms else build_duration_ms;
                    rebuild_timer = null;

                    var timer = std.time.Timer.start() catch unreachable;

                    if (runner) |*r| {
                        _ = r.kill() catch {};
                        _ = r.wait() catch {};
                    }
                    if (runner_output) |*o| {
                        o.wait();
                        o.deinit();
                        runner_output = null;
                    }

                    if (program_path == null) {
                        var program_meta = util.findprogram(allocator, binpath) catch |err| {
                            log.debug("Error finding ZX executable: {any}", .{err});
                            continue;
                        };
                        program_path = program_meta.binpath; // Owned by program_meta, we keep it
                        program_meta.binpath = null;
                        program_meta.deinit(allocator);

                        const current_stat = try std.fs.cwd().statFile(program_path.?);
                        build_state.binary_path = try allocator.dupe(u8, program_path.?);
                        build_state.last_binary_mtime = current_stat.mtime;
                    }

                    const runnable_path = try util.getRunnablePath(allocator, program_path.?);

                    if (clear_on_restart) {
                        try ctx.writer.print("\x1b[2J\x1b[H", .{});
                    }

                    if (rebuilding_shown) {
                        const restart_prefix: []const u8 = if (rebuilding_shown) "\r" else "\n";
                        if (use_spinner) {
                            var spinner = ctx.spinner;
                            if (!rebuilding_shown) try ctx.writer.print("\n", .{});
                            spinner.updateStyle(.{ .frames = zli.Spinner.SpinnerStyles.dots2, .refresh_rate_ms = 80 });
                            try spinner.start("{s}Restarting...{s}", .{ Colors.purple, Colors.reset });
                        } else {
                            try ctx.writer.print("{s}{s}↻ {s}Restarting...{s}", .{ restart_prefix, Colors.purple, Colors.bold, Colors.reset });
                        }
                    }

                    var runner_args = std.ArrayList([]const u8).empty;
                    defer runner_args.deinit(allocator);
                    try runner_args.appendSlice(allocator, &.{ runnable_path, "--cli-command", "dev" });

                    runner = std.process.Child.init(runner_args.items, allocator);
                    runner.?.env_map = &env_map;
                    runner.?.stderr_behavior = .Pipe;
                    runner.?.stdout_behavior = .Pipe;

                    try runner.?.spawn();

                    runner_output = try util.captureChildOutput(ctx.allocator, &runner.?, .{
                        .stderr = .{ .mode = .first_line_then_transparent, .target = .stderr },
                        .stdout = .{ .mode = .transparent, .target = .stdout },
                    });

                    runner_output.?.waitForFirstLine();

                    const restart_time_ms = timer.lap() / std.time.ns_per_ms;

                    if (rebuilding_shown) {
                        if (use_spinner) {
                            var spinner = ctx.spinner;
                            if (wall_build_ms > 0) {
                                try spinner.succeed("{s}Restarted in {s}[{d} + {d:.0}]ms{s}", .{ Colors.green, Colors.gray, wall_build_ms, restart_time_ms, Colors.reset });
                            } else {
                                try spinner.succeed("{s}Restarted in {d:.0}ms{s}", .{ Colors.green, restart_time_ms, Colors.reset });
                            }
                        } else {
                            if (wall_build_ms > 0) {
                                try ctx.writer.print("\r{s}✓ {s}Restarted in {s}[{d} + {d:.0}]ms{s}\x1b[K\n", .{ Colors.green, Colors.bold, Colors.gray, wall_build_ms, restart_time_ms, Colors.reset });
                            } else {
                                try ctx.writer.print("\r{s}✓ {s}Restarted in {d:.0} ms{s}\x1b[K\n", .{ Colors.green, Colors.bold, restart_time_ms, Colors.reset });
                            }
                        }
                    }

                    if (!is_first_run) {
                        try ctx.writer.print("\n", .{});
                    }
                    printFirstLine(&runner_output.?, is_first_run);
                    is_first_run = false;
                    dev_server.notifyReload();

                    const current_stat = std.fs.cwd().statFile(program_path.?) catch |err| {
                        log.debug("Failed to stat binary after restart: {any}", .{err});
                        continue;
                    };
                    build_state.markRestartComplete(current_stat.mtime);
                    rebuilding_shown = false;
                },
            }
        }
        line_writer.clearRetainingCapacity();
    } else |err| {
        if (err != error.EndOfStream) return err;
    }
}

/// Print the first captured line (prefer stderr, fallback to stdout)
fn printFirstLine(output: *util.ChildOutput, is_first_run: bool) void {
    if (output.getLastStderrLine()) |first_line| {
        if (first_line.len > 0) {
            if (!is_first_run) {
                std.debug.print("{s}╭─{s}[{s}Application Logs{s}]\n", .{ Colors.gray, Colors.reset, Colors.purple, Colors.reset });
            }
            std.debug.print("{s}\n", .{first_line});
        }
    } else if (output.getLastStdoutLine()) |first_line| {
        if (first_line.len > 0) {
            std.debug.print("{s}\n", .{first_line});
        }
    }
}
