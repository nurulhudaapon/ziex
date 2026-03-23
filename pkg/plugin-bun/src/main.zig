const std = @import("std");

const EventType = enum { start, result, end, @"error" };
const BuildEvent = struct {
    id: u32,
    name: []const u8,
    type: EventType,
    success: ?bool = null,
    @"error": ?[]const u8 = null,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // --- Flags --- //
    var bun_path: []const u8 = "bun"; // default to "bun" in PATH
    var outdir_path: ?[]const u8 = null;
    const runner_script = @embedFile("builder.ts");

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--bun-path")) bun_path = args.next() orelse return error.MissingBunPath;
        if (std.mem.eql(u8, arg, "--outdir")) outdir_path = args.next() orelse return error.MissingOutdirPath;
    }

    const input_json = try std.fs.File.stdin().readToEndAlloc(allocator, 64 * 1024 * 1024);
    defer allocator.free(input_json);

    // Parse and inject outdir into each build config
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, input_json, .{});
    defer parsed.deinit();

    const builds = parsed.value.array.items;
    const build_count = builds.len;

    if (outdir_path) |od| {
        for (builds) |*build_item| {
            const config_ptr = build_item.object.getPtr("config").?;
            try config_ptr.object.put("outdir", .{ .string = od });
        }
    }

    // Re-serialize with injected outdir
    const modified_json = try std.json.Stringify.valueAlloc(allocator, parsed.value, .{});
    defer allocator.free(modified_json);

    var child = std.process.Child.init(
        &.{ bun_path, "-e", runner_script },
        allocator,
    );
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Inherit;
    try child.spawn();

    // Write config to bun's stdin, then close so bun sees EOF
    try child.stdin.?.writeAll(modified_json);
    child.stdin.?.close();
    child.stdin = null;

    var progress = std.Progress.start(.{
        .root_name = "bun build",
        .estimated_total_items = build_count,
    });
    defer progress.end();

    const NodeMap = std.StringHashMap(std.Progress.Node);
    var nodes = NodeMap.init(allocator);
    defer {
        var it = nodes.valueIterator();
        while (it.next()) |n| n.end();
        nodes.deinit();
    }

    var failed: usize = 0;
    failed = failed; // silence unused

    var stdout = child.stdout.?;
    var buffer: [4096]u8 = undefined;
    var streaming_reader = stdout.readerStreaming(&buffer);
    const io_reader = &streaming_reader.interface;
    var line_writer = std.Io.Writer.Allocating.init(allocator);
    defer line_writer.deinit();

    var aa = std.heap.ArenaAllocator.init(allocator);
    const arena = aa.allocator();
    defer aa.deinit();
    while (io_reader.streamDelimiter(&line_writer.writer, '\n')) |_| {
        const line = line_writer.written();
        _ = io_reader.takeByte() catch break;

        const ev_parsed = std.json.parseFromSlice(BuildEvent, allocator, line, .{
            .ignore_unknown_fields = true,
        }) catch continue; // skip malformed lines
        defer ev_parsed.deinit();
        const ev = ev_parsed.value;

        const name = try std.fmt.allocPrint(arena, "{s} ({d})", .{ ev.name, ev.id });

        switch (ev.type) {
            .start => {
                const node = progress.start(name, 0);
                try nodes.put(name, node);
            },
            .result => {
                if (ev.success == false) failed += 1;
            },
            .@"error" => {
                failed += 1;
                if (ev.@"error") |msg| {
                    std.debug.print("bun build [{s}] error: {s}\n", .{ ev.name, msg });
                }
            },
            .end => {
                if (nodes.fetchRemove(name)) |kv| {
                    kv.value.end();
                }
                progress.completeOne();
            },
        }

        line_writer.clearRetainingCapacity();
    } else |err| {
        if (err == error.EndOfStream) {}
    }

    const term = child.wait() catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Failed to execute bun: executable not found at '{s}'\n", .{bun_path});
            return error.BunNotFound;
        }
        std.debug.print("Failed to wait for bun process: {any}\n", .{err});
        return error.WaitFailed;
    };
    const exit_code: u8 = switch (term) {
        .Exited => |c| c,
        else => 1,
    };

    if (exit_code != 0 or failed > 0) {
        std.debug.print("bun build: {d} build(s) failed\n", .{failed});
        std.process.exit(1);
    }
}
