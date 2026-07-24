const std = @import("std");
const cli = @import("cli");
const CommandContext = @import("shared/context.zig").CommandContext;
const log = std.log.scoped(.cli);
const core_lang = @import("core_lang");
const tui = @import("../tui/main.zig");
const colors = tui.Colors;
const Builder = @import("dev/Builder.zig");
const Diagnostics = @import("dev/Diagnostics.zig");

pub const command: cli.Command = .{
    .name = .fmt,
    .help_short = "Format .zx files or directories.",
    .named_args = &.{
        cli.Argument.init(.stdio, bool, .{
            .default_value = false,
            .help = "Read from stdin and write formatted output to stdout",
        }),
        cli.Argument.init(.stdout, bool, .{
            .default_value = false,
            .help = "Write formatted output to stdout instead of disk",
        }),
        cli.Argument.init(.@"error", bool, .{
            .default_value = false,
            .help = "Read zig build error output from stdin and pretty-print it (e.g. zig build 2>&1 | zx fmt --error)",
        }),
    },
    .positional_args = &.{
        cli.Argument.init(.paths, []const []const u8, .{
            .count = .unlimited,
            .default_value = &.{},
            .help = "Paths to .zx files or directories",
        }),
    },
};

pub fn run(ctx: CommandContext, args: anytype) !void {
    const app = ctx.app;
    const io = app.io;

    const use_stdio = args.stdio;
    const use_stdout = args.stdout;
    const use_error = args.@"error";

    if (use_error) {
        try formatErrorFromStdin(io, ctx.allocator, ctx.writer);
        return;
    }

    if (use_stdio) {
        try formatFromStdin(io, ctx.allocator, ctx.writer);
        return;
    }

    const paths = args.paths;
    if (paths.len == 0) {
        try ctx.writer.print("{s}No paths were given.{s}\n", .{ colors.yellow, colors.reset });
        try ctx.writer.print("\nUsage:\n\n", .{});
        try ctx.writer.print("  {s}zx fmt{s} {s}{s}app/pages/page.zx{s}  {s}# Format a single file{s}\n\n", .{
            colors.cyan,
            colors.reset,
            colors.bold,
            colors.gray,
            colors.reset,
            colors.gray,
            colors.reset,
        });
        try ctx.writer.print("  {s}zx fmt{s} {s}{s}app/pages{s}  {s}# Format all .zx files in a directory{s}\n\n", .{
            colors.cyan,
            colors.reset,
            colors.bold,
            colors.gray,
            colors.reset,
            colors.gray,
            colors.reset,
        });
        return;
    }

    for (paths) |path| {
        var dir = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch |err| switch (err) {
            error.NotDir => {
                try formatFile(ctx.allocator, io, ctx.writer, std.Io.Dir.cwd(), path, path, use_stdout);
                continue;
            },
            else => continue,
        };

        defer dir.close(io);
        try formatDir(ctx.allocator, io, ctx.writer, path, use_stdout);
    }
}

fn formatErrorFromStdin(io: std.Io, allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {
    var stdin_file = std.Io.File.stdin();
    var raw_buf: [8192]u8 = undefined;
    var streaming_reader = stdin_file.readerStreaming(io, &raw_buf);
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

    if (diagnostics.items.len == 0) return;

    Diagnostics.remap(allocator, diagnostics.items);
    const deduped = Diagnostics.dedupe(allocator, diagnostics.items);
    diagnostics.shrinkRetainingCapacity(deduped.len);

    const formatted = try Diagnostics.formatOxlint(allocator, deduped);
    defer allocator.free(formatted);

    try writer.writeAll(formatted);
}

fn formatFromStdin(io: std.Io, allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {
    var reader = std.Io.File.stdin().reader(io, &.{});
    var buffer: std.Io.Writer.Allocating = .init(allocator);
    _ = try reader.interface.streamRemaining(&buffer.writer);
    const input = try buffer.toOwnedSliceSentinel(0);
    defer allocator.free(input);

    var format_result = try core_lang.Ast.fmt(allocator, input);
    defer format_result.deinit(allocator);

    if (format_result.source == null) {
        for (format_result.diagnostics.items) |d| {
            log.err("{}:{}: {s}", .{ d.start_line + 1, d.start_column + 1, d.message });
        }
        return;
    }

    try writer.writeAll(format_result.source.?);
}

fn formatFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    writer: *std.Io.Writer,
    base_dir: std.Io.Dir,
    sub_path: []const u8,
    full_path: []const u8,
    use_stdout: bool,
) !void {
    if (!std.mem.endsWith(u8, sub_path, ".zx")) {
        return; // Skip non-.zx files
    }
    const source = try base_dir.readFileAlloc(
        io,
        sub_path,
        allocator,
        .unlimited,
    );
    defer allocator.free(source);

    const source_z = try allocator.dupeSentinel(u8, source, 0);
    defer allocator.free(source_z);

    var format_result = try core_lang.Ast.fmt(allocator, source_z);
    defer format_result.deinit(allocator);

    if (format_result.source == null) {
        for (format_result.diagnostics.items) |d| {
            log.err("{s}:{}:{}: {s}", .{ full_path, d.start_line + 1, d.start_column + 1, d.message });
        }
        return;
    }

    const formatted = format_result.source.?;

    if (use_stdout) {
        try writer.writeAll(formatted);
        return;
    }

    // Skip writing if content unchanged
    if (std.mem.eql(u8, formatted, source)) {
        return;
    }

    // Write formatted content back to file
    var atomic_file = try base_dir.createFileAtomic(io, sub_path, .{ .replace = true });
    defer atomic_file.deinit(io);

    try atomic_file.file.writeStreamingAll(io, formatted);
    try atomic_file.replace(io);
    try writer.print("{s}\n", .{full_path});
}

fn formatDir(
    allocator: std.mem.Allocator,
    io: std.Io,
    writer: *std.Io.Writer,
    path: []const u8,
    use_stdout: bool,
) !void {
    var dir = try std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true });
    defer dir.close(io);

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;

        // Check if file ends with .zx before processing
        if (!std.mem.endsWith(u8, entry.path, ".zx")) continue;

        // Construct full path relative to current working directory
        // Normalize path by removing leading ./ if present
        const normalized_path = if (std.mem.startsWith(u8, path, "./")) path[2..] else path;
        const full_path = try std.fs.path.join(allocator, &.{ normalized_path, entry.path });
        defer allocator.free(full_path);

        // Read file using entry.dir (which is the directory containing the file)
        const source = try entry.dir.readFileAlloc(
            io,
            entry.basename,
            allocator,
            .limited(std.math.maxInt(usize)),
        );
        defer allocator.free(source);

        const source_z = try allocator.dupeSentinel(u8, source, 0);
        defer allocator.free(source_z);

        var format_result = try core_lang.Ast.fmt(allocator, source_z);
        defer format_result.deinit(allocator);

        if (format_result.source == null) {
            for (format_result.diagnostics.items) |d| {
                log.err("{s}:{}:{}: {s}", .{ full_path, d.start_line + 1, d.start_column + 1, d.message });
            }
            continue;
        }

        const formatted = format_result.source.?;

        if (use_stdout) {
            try writer.writeAll(formatted);
            continue;
        }

        // Skip writing if content unchanged
        if (std.mem.eql(u8, formatted, source)) {
            continue;
        }

        // Write formatted content back to file using entry.dir
        var atomic_file = try entry.dir.createFileAtomic(io, entry.basename, .{ .replace = true });
        defer atomic_file.deinit(io);

        try atomic_file.file.writeStreamingAll(io, formatted);
        try atomic_file.replace(io);
        try writer.print("{s}\n", .{full_path});
    }
}
