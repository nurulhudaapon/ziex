const std = @import("std");

const EventType = enum { start, result, end, @"error" };
const BuildEvent = struct {
    id: u32,
    name: []const u8,
    type: EventType,
    success: ?bool = null,
    @"error": ?[]const u8 = null,
    dependencies: []const []const u8 = &.{},
};

pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const allocator = gpa.allocator();

    // --- Flags --- //
    var node_path: []const u8 = "node"; // default to "node" in PATH
    var outdir_path: ?[]const u8 = null;
    var dep_file_path: ?[]const u8 = null;
    const runner_script = @embedFile("builder.js");

    var args = try init.minimal.args.iterateAllocator(allocator);
    defer args.deinit();
    _ = args.next(); // skip program name

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--node-path")) node_path = args.next() orelse return error.MissingNodePath;
        if (std.mem.eql(u8, arg, "--outdir")) outdir_path = args.next() orelse return error.MissingOutdirPath;
        if (std.mem.eql(u8, arg, "--dep-file")) dep_file_path = args.next() orelse return error.MissingDepFilePath;
    }

    // Read stdin into memory
    var stdin_buffer: [4096]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(init.io, &stdin_buffer);
    var stdin_writer = std.Io.Writer.Allocating.init(allocator);
    defer stdin_writer.deinit();
    _ = try stdin_reader.interface.streamRemaining(&stdin_writer.writer);
    const input_json = try stdin_writer.toOwnedSlice();
    defer allocator.free(input_json);

    // Parse and inject outdir into each build config
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, input_json, .{});
    defer parsed.deinit();

    const builds = parsed.value.array.items;
    const build_count = builds.len;

    if (outdir_path) |od| {
        for (builds) |*build_item| {
            const config_ptr = build_item.object.getPtr("config").?;
            try config_ptr.object.put(allocator, "outdir", .{ .string = od });
        }
    }

    // Re-serialize with injected outdir
    const modified_json = try std.json.Stringify.valueAlloc(allocator, parsed.value, .{});
    defer allocator.free(modified_json);

    var child = try std.process.spawn(init.io, .{
        .argv = &.{ node_path, "-e", runner_script },
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .inherit,
    });

    defer if (child.id != null) {
        _ = child.wait(init.io) catch {};
    };

    if (child.stdin) |stdin_file| {
        try stdin_file.writeStreamingAll(init.io, modified_json);
        stdin_file.close(init.io);
        child.stdin = null;
    }

    var progress = std.Progress.start(init.io, .{
        .root_name = "esbuild",
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

    // Collect dependencies for dep file
    var all_deps = std.ArrayList([]const u8).empty;
    defer all_deps.deinit(allocator);

    if (child.stdout) |stdout_file| {
        var buffer: [4096]u8 = undefined;
        var streaming_reader = stdout_file.readerStreaming(init.io, &buffer);
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
                    // Dupe into `allocator` (lives for the whole program), NOT the
                    // block-scoped `arena` which is freed when this block exits and
                    // before `writeDepFile` reads `all_deps`.
                    for (ev.dependencies) |dep| {
                        try all_deps.append(allocator, try allocator.dupe(u8, dep));
                    }
                },
                .@"error" => {
                    failed += 1;
                    if (ev.@"error") |msg| {
                        std.debug.print("esbuild [{s}] error: {s}\n", .{ ev.name, msg });
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
    }

    // Write dep file before potential exit(1)
    if (dep_file_path) |dfp| {
        writeDepFile(allocator, init.io, dfp, outdir_path orelse "dist", all_deps.items) catch |err| {
            std.debug.print("Failed to write dep file: {any}\n", .{err});
        };
    }

    const term = child.wait(init.io) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Failed to execute node: executable not found at '{s}'\n", .{node_path});
            return error.NodeNotFound;
        }
        std.debug.print("Failed to wait for node process: {any}\n", .{err});
        return error.WaitFailed;
    };
    const exit_code: u8 = switch (term) {
        .exited => |c| c,
        else => 1,
    };

    if (exit_code != 0 or failed > 0) {
        std.debug.print("esbuild: {d} build(s) failed\n", .{failed});
        std.process.exit(1);
    }
}

fn writeDepFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8, target: []const u8, deps: []const []const u8) !void {
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(allocator);
    try buf.appendSlice(allocator, target);
    try buf.appendSlice(allocator, ":");
    for (deps) |dep| {
        try buf.appendSlice(allocator, " ");
        for (dep) |c| {
            if (c == ' ') {
                try buf.appendSlice(allocator, "\\ ");
            } else {
                try buf.append(allocator, c);
            }
        }
    }
    try buf.appendSlice(allocator, "\n");
    const f = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer f.close(io);
    try f.writeStreamingAll(io, buf.items);
}
