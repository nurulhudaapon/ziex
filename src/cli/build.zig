const std = @import("std");

const util = @import("shared/util.zig");
const context = @import("shared/context.zig");
const Builder = @import("dev/Builder.zig");
const Diagnostics = @import("dev/Diagnostics.zig");
const tui = @import("../tui/main.zig");
const cli_args = @import("root.zig");

const CommandContext = context.CommandContext;
const Colors = tui.Colors;
const log = std.log.scoped(.cli);
pub const command = cli_args.build;

pub fn run(ctx: CommandContext, args: anytype) !void {
    const app = ctx.app;
    const io = app.io;
    const allocator = ctx.allocator;

    var build_args = std.ArrayList([]const u8).empty;
    defer build_args.deinit(allocator);
    try build_args.appendSlice(allocator, &.{ args.@"zig-path", "build" });

    var i_build_args = std.mem.splitSequence(u8, args.@"build-args", " ");
    while (i_build_args.next()) |arg| {
        const trimmed_arg = std.mem.trim(u8, arg, " ");
        if (std.mem.eql(u8, trimmed_arg, "")) continue;
        try build_args.append(allocator, trimmed_arg);
    }

    var system = try util.spawnZig(io, .{
        .argv = build_args.items,
        .stderr = .pipe,
        .stdout = .ignore,
    });
    defer system.kill(io);

    var spinner = ctx.spinner;
    spinner.updateStyle(.{ .frames = tui.Spinner.SpinnerStyles.dots2, .refresh_rate_ms = 80 });
    try spinner.start("{s}Building...{s}", .{ Colors.cyan, Colors.reset });

    const start_ts = std.Io.Timestamp.now(io, .awake);

    const formatted = formatBuildErrors(io, allocator, &system) catch |err| {
        spinner.fail("{s}Build failed{s}", .{ Colors.red, Colors.reset }) catch {};
        return err;
    };
    defer if (formatted) |f| allocator.free(f);

    const term = try system.wait(io);
    const elapsed_ms: u64 = @intCast(start_ts.durationTo(std.Io.Timestamp.now(io, .awake)).toMilliseconds());
    const elapsed_s = @as(f64, @floatFromInt(elapsed_ms)) / 1000.0;

    const failed = switch (term) {
        .exited => |code| code != 0,
        else => true,
    };

    if (failed) {
        try spinner.fail("{s}Build failed {s}({d:.2}s){s}", .{ Colors.red, Colors.gray, elapsed_s, Colors.reset });
        if (formatted) |f| try ctx.writer.writeAll(f);
        switch (term) {
            .exited => |code| std.process.exit(code),
            else => std.process.exit(1),
        }
    }

    try spinner.succeed("{s}Built {s}({d:.2}s){s}", .{ Colors.green, Colors.gray, elapsed_s, Colors.reset });
    if (formatted) |f| try ctx.writer.writeAll(f);
}

fn formatBuildErrors(
    io: std.Io,
    allocator: std.mem.Allocator,
    system: *std.process.Child,
) !?[]u8 {
    var stderr_file = system.stderr.?;
    var raw_buf: [8192]u8 = undefined;
    var streaming_reader = stderr_file.readerStreaming(io, &raw_buf);
    const io_reader = &streaming_reader.interface;

    var diagnostics = std.ArrayList(Builder.Diagnostic).empty;
    defer {
        for (diagnostics.items) |d| {
            allocator.free(d.file);
            allocator.free(d.message);
            if (d.source_line) |sl| allocator.free(sl);
            if (d.caret_line) |cl| allocator.free(cl);
        }
        diagnostics.deinit(allocator);
    }

    var line_writer = std.Io.Writer.Allocating.init(allocator);
    defer line_writer.deinit();

    while (io_reader.streamDelimiter(&line_writer.writer, '\n')) |_| {
        const line = line_writer.written();
        _ = io_reader.takeByte() catch {};

        if (Builder.parseDiagnostic(allocator, line)) |diag| {
            try diagnostics.append(allocator, diag);
        } else if (diagnostics.items.len > 0) {
            var last_diag = &diagnostics.items[diagnostics.items.len - 1];
            if (last_diag.source_line == null) {
                if (line.len > 0) {
                    last_diag.source_line = try allocator.dupe(u8, line);
                    line_writer.clearRetainingCapacity();
                    continue;
                }
            } else if (last_diag.caret_line == null) {
                if (std.mem.indexOfAny(u8, line, "^~") != null) {
                    last_diag.caret_line = try allocator.dupe(u8, line);
                    line_writer.clearRetainingCapacity();
                    continue;
                }
            }
        }

        line_writer.clearRetainingCapacity();
    } else |err| {
        if (err != error.EndOfStream) return err;
    }

    if (diagnostics.items.len == 0) return null;

    Diagnostics.remap(allocator, diagnostics.items, .{});
    const deduped = Diagnostics.dedupe(allocator, diagnostics.items);
    diagnostics.shrinkRetainingCapacity(deduped.len);

    return try Diagnostics.formatOxlint(allocator, deduped);
}
