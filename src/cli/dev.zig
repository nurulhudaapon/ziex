pub fn register(writer: *std.Io.Writer, reader: *std.Io.Reader, allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(writer, reader, allocator, .{
        .name = "dev",
        .description = "Start the app in development mode with rebuild on change",
    }, dev);

    try cmd.addFlag(flag.binpath_flag);
    try cmd.addFlag(flag.build_args);
    try cmd.addFlag(.{
        .name = "progress",
        .description = "Show full build progress output from zig build",
        .type = .Bool,
        .default_value = .{ .Bool = false },
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
    const build_args_str = ctx.flag("build-args", []const u8);
    const show_progress = ctx.flag("progress", bool);
    const show_underline = ctx.flag("tui-underline", bool);
    const use_spinner = ctx.flag("tui-spinner", bool);
    const clear_on_restart = ctx.flag("tui-clear", bool);
    var build_args = std.mem.splitSequence(u8, build_args_str, " ");

    var build_args_array = std.ArrayList([]const u8).empty;
    try build_args_array.append(allocator, "zig");
    try build_args_array.append(allocator, "build");
    while (build_args.next()) |arg| {
        const trimmed_arg = std.mem.trim(u8, arg, " ");
        if (std.mem.eql(u8, trimmed_arg, "")) continue;
        try build_args_array.append(allocator, trimmed_arg);
    }

    jsutil.buildjs(ctx, binpath, true, false) catch |err| {
        log.debug("Error building JavaScript! {any}", .{err});
    };

    {
        const build_cmd_str = try std.mem.join(allocator, " ", build_args_array.items);
        defer allocator.free(build_cmd_str);
        log.debug("First time building, we will run `{s}`", .{build_cmd_str});
        var build_builder = std.process.Child.init(build_args_array.items, allocator);
        try build_builder.spawn();
        _ = try build_builder.wait();
    }

    try build_args_array.append(allocator, "--watch");

    // Add --summary all in silent mode to get detailed timing info
    // if (!show_progress) {
    try build_args_array.append(allocator, "--summary");
    try build_args_array.append(allocator, "all");
    // }

    var builder = std.process.Child.init(build_args_array.items, allocator);

    // Only pipe stderr if we're NOT showing progress (to suppress output)
    if (!show_progress) {
        builder.stderr_behavior = .Pipe;
        builder.stdout_behavior = .Pipe;
    }
    // Otherwise use default .Inherit to show full build output

    try builder.spawn();
    defer _ = builder.kill() catch unreachable;

    const watch_cmd_str = try std.mem.join(allocator, " ", build_args_array.items);
    defer allocator.free(watch_cmd_str);
    log.debug("Building with watch mode `{s}` (progress={any})", .{ watch_cmd_str, show_progress });

    log.debug("Building complete, finding ZX executable", .{});
    var program_meta = util.findprogram(allocator, binpath) catch |err| {
        try ctx.writer.print("Error finding ZX executable! {any}\n", .{err});
        return err;
    };
    defer program_meta.deinit(allocator);

    const program_path = program_meta.binpath orelse {
        try ctx.writer.print("Error finding ZX exedcutable!\n", .{});
        return;
    };

    const runnable_program_path = try util.getRunnablePath(allocator, program_path);

    // TODO: Move logic of building js to the post transpilation process in the build system steps
    var need_js_build = true;
    jsutil.buildjs(ctx, binpath, true, true) catch |err| {
        log.debug("Error building JavaScript! {any}", .{err});
        if (err == error.PackageJsonNotFound) need_js_build = false;
    };

    var runner = std.process.Child.init(&.{ runnable_program_path, "--cli-command", "dev" }, allocator);
    runner.stderr_behavior = .Pipe;
    runner.stdout_behavior = .Pipe;
    defer {
        _ = runner.kill() catch {};
        _ = runner.wait() catch {};
    }

    // Start timer for server startup
    var startup_timer = try std.time.Timer.start();

    // Print starting message
    if (use_spinner) {
        try ctx.writer.print("\n", .{});
        var spinner = ctx.spinner;
        spinner.updateStyle(.{ .frames = zli.Spinner.SpinnerStyles.dots2, .refresh_rate_ms = 80 });
        try spinner.start("{s}Starting  ZX App...{s}\x1b[K", .{ Colors.cyan, Colors.reset });
    } else {
        const underline_code = if (show_underline) Colors.underline else "";
        try ctx.writer.print("{s}{s}Starting ZX App...{s}", .{ Colors.cyan, underline_code, Colors.reset });
    }

    try runner.spawn();

    var runner_output = try util.captureChildOutput(ctx.allocator, &runner, .{
        .stderr = .{ .mode = .first_line_then_transparent, .target = .stderr, .transparent_delay_ms = 100 },
        .stdout = .{ .mode = .transparent, .target = .stdout },
    });
    defer runner_output.deinit();

    // Wait for the first line to be captured, then print it synchronously
    runner_output.waitForFirstLine();

    // Print completion with timing
    const startup_time_ms = startup_timer.lap() / std.time.ns_per_ms;
    if (use_spinner) {
        var spinner = ctx.spinner;
        try spinner.succeed("{s}Started  ZX App in {s}{d:.0}ms{s}\x1b[K", .{ Colors.cyan, Colors.green, startup_time_ms, Colors.reset });
        if (show_underline) {
            try ctx.writer.print("{s}─────────────────────────────────────────{s}\n", .{ Colors.gray, Colors.reset });
        }
    } else {
        const underline_code = if (show_underline) Colors.underline else "";
        try ctx.writer.print("\r{s}{s}Starting ZX App... {s}done in {d:.0} ms{s}\x1b[K\n", .{ Colors.cyan, underline_code, Colors.green, startup_time_ms, Colors.reset });
    }

    printFirstLine(&runner_output);

    // Get initial binary modification time
    const initial_stat = try std.fs.cwd().statFile(program_path);

    // Create build watcher (only needed in silent mode)
    var build_watcher: ?builder_util.BuildWatcher = if (!show_progress)
        builder_util.BuildWatcher.init(
            allocator,
            builder.stderr.?,
            program_path,
            initial_stat.mtime,
        )
    else
        null;

    // Spawn thread to watch build output (only in silent mode)
    const watcher_thread: ?std.Thread = if (build_watcher) |*watcher|
        try std.Thread.spawn(.{}, builder_util.watchBuildOutput, .{watcher})
    else
        null;
    defer if (watcher_thread) |thread| thread.join();

    // For progress mode: track binary mtime manually
    var last_binary_mtime = initial_stat.mtime;
    var last_restart_time_ns: i128 = 0;

    while (true) {
        std.Thread.sleep(std.time.ns_per_ms * 1);

        // Check for restart condition
        const should_restart = if (build_watcher) |*watcher|
            watcher.shouldRestart()
        else blk: {
            // Progress mode: poll binary mtime manually
            const stat = std.fs.cwd().statFile(program_path) catch continue;
            const changed = stat.mtime != last_binary_mtime;
            if (changed) {
                const now = std.time.nanoTimestamp();
                const time_since_last = now - last_restart_time_ns;
                // Only restart if enough time has passed (debounce)
                if (time_since_last >= std.time.ns_per_ms * 500) {
                    last_binary_mtime = stat.mtime;
                    break :blk true;
                }
            }
            break :blk false;
        };

        if (should_restart) {
            log.debug("Processing restart request...", .{});

            // Get build duration from watcher (if available)
            const build_duration_ms = if (build_watcher) |*watcher|
                watcher.getBuildDurationMs()
            else
                0;

            var timer = try std.time.Timer.start();

            // TODO: Move logic of building js to the post transpilation process in the build system steps
            if (need_js_build) jsutil.buildjs(ctx, binpath, true, true) catch |err| {
                log.debug("Error bundling JavaScript! {any}", .{err});
            };

            _ = runner.kill() catch {};
            _ = runner.wait() catch {};
            runner_output.wait();
            runner_output.deinit();

            if (builtin.os.tag == .windows) {
                // remove the tmp and copy the new zx.exe
                _ = try util.getRunnablePath(allocator, program_path);

                _ = try builder.kill();
                if (!show_progress) {
                    builder.stderr_behavior = .Pipe;
                    builder.stdout_behavior = .Pipe;
                }
                try builder.spawn();
                if (build_watcher) |*watcher| {
                    watcher.builder_stderr = builder.stderr.?;
                }
            }

            // Clear visible screen before restart
            if (clear_on_restart) {
                try ctx.writer.print("\x1b[2J\x1b[H", .{});
            }

            if (use_spinner) {
                try ctx.writer.print("\n", .{});
                var spinner = ctx.spinner;
                spinner.updateStyle(.{ .frames = zli.Spinner.SpinnerStyles.dots2, .refresh_rate_ms = 80 });
                try spinner.start("{s}Restarting ZX App...{s}", .{ Colors.cyan, Colors.reset });
            } else {
                const restart_underline = if (show_underline) Colors.underline else "";
                try ctx.writer.print("\n{s}{s}Restarting ZX App...{s}", .{ Colors.cyan, restart_underline, Colors.reset });
            }

            runner = std.process.Child.init(&.{ runnable_program_path, "--cli-command", "dev" }, allocator);
            runner.stderr_behavior = .Pipe;
            runner.stdout_behavior = .Pipe;

            try runner.spawn();

            runner_output = try util.captureChildOutput(ctx.allocator, &runner, .{
                .stderr = .{ .mode = .first_line_then_transparent, .target = .stderr },
                .stdout = .{ .mode = .transparent, .target = .stdout },
            });

            runner_output.waitForFirstLine();

            // Elapsed time - show combined build + restart time
            const restart_time_ms = timer.lap() / std.time.ns_per_ms;

            if (use_spinner) {
                var spinner = ctx.spinner;
                if (build_duration_ms > 0) {
                    try spinner.succeed("{s}Restarted  ZX app in {s}[{d} + {d:.0}]ms{s}", .{ Colors.cyan, Colors.gray, build_duration_ms, restart_time_ms, Colors.reset });
                } else {
                    try spinner.succeed("{s}Restarted  ZX app in {s}{d:.0}ms{s}", .{ Colors.cyan, Colors.green, restart_time_ms, Colors.reset });
                }
                if (show_underline) {
                    try ctx.writer.print("{s}─────────────────────────────────────────{s}\n", .{ Colors.gray, Colors.reset });
                }
            } else {
                const restart_underline = if (show_underline) Colors.underline else "";
                if (build_duration_ms > 0) {
                    // // VARIATION 1: All green, space before ms
                    // try ctx.writer.print("\r{s}Restarting ZX App... {s}done in [{d} + {d:.0}] ms{s}\x1b[K\n", .{ Colors.cyan, Colors.green, build_duration_ms, restart_time_ms, Colors.reset });

                    // // VARIATION 2: Gray brackets/+, green numbers, space before ms
                    // try ctx.writer.print("{s}Restarting ZX App... {s}done in {s}[{s}{d}{s} + {s}{d:.0}{s}]{s} ms{s}\x1b[K\n", .{ Colors.cyan, Colors.green, Colors.gray, Colors.green, build_duration_ms, Colors.gray, Colors.green, restart_time_ms, Colors.gray, Colors.green, Colors.reset });

                    // // VARIATION 3: All green, NO space before ms
                    // try ctx.writer.print("{s}Restarting ZX App... {s}done in [{d} + {d:.0}]ms{s}\x1b[K\n", .{ Colors.cyan, Colors.green, build_duration_ms, restart_time_ms, Colors.reset });

                    // // VARIATION 4: Gray entire timing, space before ms
                    // try ctx.writer.print("{s}Restarting ZX App... {s}done in {s}[{d} + {d:.0}] ms{s}\x1b[K\n", .{ Colors.cyan, Colors.green, Colors.gray, build_duration_ms, restart_time_ms, Colors.reset });

                    // // VARIATION 5: Restart cyan, build yellow, brackets gray, space before ms
                    // try ctx.writer.print("{s}Restarting ZX App... {s}done in {s}[{s}{d}{s} + {s}{d:.0}{s}]{s} ms{s}\x1b[K\n", .{ Colors.cyan, Colors.green, Colors.gray, Colors.yellow, build_duration_ms, Colors.gray, Colors.cyan, restart_time_ms, Colors.gray, Colors.green, Colors.reset });

                    // // VARIATION 6: Gray brackets/+, green numbers, NO space before ms
                    // try ctx.writer.print("{s}Restarting ZX App... {s}done in {s}[{s}{d}{s} + {s}{d:.0}{s}]{s}ms{s}\x1b[K\n", .{ Colors.cyan, Colors.green, Colors.gray, Colors.green, build_duration_ms, Colors.gray, Colors.green, restart_time_ms, Colors.gray, Colors.green, Colors.reset });

                    // VARIATION 7: Whole line underlined (optional), timing in gray, NO space before ms
                    try ctx.writer.print("\r{s}{s}Restarting ZX App... {s}{s}done in {s}[{d} + {d:.0}]ms{s}\x1b[K\n", .{ Colors.cyan, restart_underline, Colors.green, restart_underline, Colors.gray, build_duration_ms, restart_time_ms, Colors.reset });
                } else {
                    // Fallback: only show restart time, whole line underlined (optional)
                    try ctx.writer.print("\r{s}{s}Restarting ZX App... {s}{s}done in {d:.0} ms{s}\x1b[K\n", .{ Colors.cyan, restart_underline, Colors.green, restart_underline, restart_time_ms, Colors.reset });
                }
            }

            printFirstLine(&runner_output);

            // Update binary mtime after restart to stay in sync
            const current_stat = std.fs.cwd().statFile(program_path) catch |err| {
                log.debug("Failed to stat binary after restart: {any}", .{err});
                continue;
            };

            // Reset restart state
            if (build_watcher) |*watcher| {
                watcher.markRestartComplete(current_stat.mtime);
            } else {
                // Progress mode: update tracking variables
                last_binary_mtime = current_stat.mtime;
                last_restart_time_ns = std.time.nanoTimestamp();
            }
            log.debug("Restart complete, ready for next build", .{});
        }
    }
}

/// Print the first captured line (prefer stderr, fallback to stdout)
fn printFirstLine(output: *util.ChildOutput) void {
    if (output.getLastStderrLine()) |first_line| {
        if (first_line.len > 0) {
            std.debug.print("{s}\n", .{first_line});
        }
    } else if (output.getLastStdoutLine()) |first_line| {
        if (first_line.len > 0) {
            std.debug.print("{s}\n", .{first_line});
        }
    }
}

const std = @import("std");
const zli = @import("zli");
const zx = @import("zx");
const builtin = @import("builtin");

const util = @import("shared/util.zig");
const flag = @import("shared/flag.zig");
const jsutil = @import("shared/js.zig");
const builder_util = @import("shared/builder.zig");
const tui = @import("../tui/main.zig");

const Colors = tui.Colors;
const log = std.log.scoped(.cli);
