pub fn register(writer: *std.Io.Writer, reader: *std.Io.Reader, allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(writer, reader, allocator, .{
        .name = "dev",
        .description = "Start the app in development mode with rebuild on change",
    }, dev);

    try cmd.addFlag(flag.binpath_flag);
    try cmd.addFlag(flag.build_args);

    return cmd;
}

const MIN_RESTART_INTERVAL_NS = std.time.ns_per_ms * 10; // 10ms
const MAX_RESTART_INTERVAL_NS = std.time.ns_per_ms * 300; // 300ms
const INTERVAL_STEP_NS = std.time.ns_per_ms / 10; // Increase by 0.1ms each step
const BIN_DIR = "zig-out/bin";

fn dev(ctx: zli.CommandContext) !void {
    const allocator = ctx.allocator;
    const binpath = ctx.flag("binpath", []const u8);
    const build_args_str = ctx.flag("build-args", []const u8);
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
    var builder = std.process.Child.init(build_args_array.items, allocator);

    try builder.spawn();
    defer _ = builder.kill() catch unreachable;

    const watch_cmd_str = try std.mem.join(allocator, " ", build_args_array.items);
    defer allocator.free(watch_cmd_str);
    log.debug("Building with watch mode `{s}`", .{watch_cmd_str});

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

    var need_js_build = true;
    jsutil.buildjs(ctx, binpath, true, true) catch |err| {
        log.debug("Error building JavaScript! {any}", .{err});
        if (err == error.PackageJsonNotFound) need_js_build = false;
    };

    var runner = std.process.Child.init(&.{ runnable_program_path, "--cli-command", "dev" }, allocator);
    runner.stderr_behavior = .Pipe;
    runner.stdout_behavior = .Pipe;

    try runner.spawn();
    std.debug.print("{s}Running ZX Dev Server...{s}\n", .{ Colors.cyan, Colors.reset });

    // Capture first line from stderr, then continue in transparent mode
    var runner_output = try util.captureChildOutput(ctx.allocator, &runner, .{
        .stderr = .{ .mode = .first_line_then_transparent, .target = .stderr },
        .stdout = .{ .mode = .transparent, .target = .stdout },
    });

    // Wait for the first line to be captured, then print it synchronously
    runner_output.waitForFirstLine();
    printFirstLine(&runner_output);

    var bin_mtime: i128 = 0;
    var current_interval_ns: u64 = MIN_RESTART_INTERVAL_NS;

    while (true) {
        std.Thread.sleep(current_interval_ns);
        const stat = try std.fs.cwd().statFile(program_path);

        const should_restart = stat.mtime != bin_mtime and bin_mtime != 0;
        if (should_restart) {
            var timer = try std.time.Timer.start();

            if (need_js_build) jsutil.buildjs(ctx, binpath, true, true) catch |err| {
                log.debug("Error bundling JavaScript! {any}", .{err});
            };

            _ = try runner.kill();
            if (builtin.os.tag == .windows) {
                // remove the tmp and copy the new zx.exe
                _ = try util.getRunnablePath(allocator, program_path);

                _ = try builder.kill();
                try builder.spawn();
            }

            // Print restart message right before spawning (after all build/kill operations)
            // Clear the current line (in case "watching..." text is there) and print without newline so we can overwrite it
            try ctx.writer.print("\r\x1b[2K{s}Restarting ZX App...{s}", .{ Colors.cyan, Colors.reset });

            try runner.spawn();

            // Capture first line from stderr, then continue in transparent mode
            var restart_output = try util.captureChildOutput(ctx.allocator, &runner, .{
                .stderr = .{ .mode = .first_line_then_transparent, .target = .stderr },
                .stdout = .{ .mode = .transparent, .target = .stdout },
            });

            // Wait for the first line to be captured, then print it synchronously
            restart_output.waitForFirstLine();

            // Elapsed time - overwrite the restart message with completion message using \r
            const elapsed_time_ms = timer.lap() / std.time.ns_per_ms;
            try ctx.writer.print("\r{s}Restarting ZX App... {s}done in {d:.0} ms {s}\x1b[K\n", .{ Colors.cyan, Colors.green, elapsed_time_ms, Colors.reset });

            printFirstLine(&restart_output);

            // Reset interval to minimum when changes are detected
            current_interval_ns = MIN_RESTART_INTERVAL_NS;
            log.debug("Restart interval reset to {d}ms", .{current_interval_ns / std.time.ns_per_ms});
        } else {
            // Gradually increase interval up to maximum when no changes
            if (current_interval_ns < MAX_RESTART_INTERVAL_NS) {
                // const old_interval = current_interval_ns;
                current_interval_ns = @min(current_interval_ns + INTERVAL_STEP_NS, MAX_RESTART_INTERVAL_NS);
                // if (old_interval != current_interval_ns) {
                //     log.debug("No changes detected, increasing restart interval to {d}ms", .{current_interval_ns / std.time.ns_per_ms});
                // }
            }
        }
        if (should_restart or bin_mtime == 0) bin_mtime = stat.mtime;
    }
}

const std = @import("std");
const zli = @import("zli");
const zx = @import("zx");
const builtin = @import("builtin");

const util = @import("shared/util.zig");
const flag = @import("shared/flag.zig");
const jsutil = @import("shared/js.zig");
const tui = @import("../tui/main.zig");

const Colors = tui.Colors;
const log = std.log.scoped(.cli);

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
