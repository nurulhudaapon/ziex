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

    var args = try init.minimal.args.iterateAllocator(allocator);
    defer args.deinit();
    _ = args.next(); // skip program name

    // --- Flags --- //
    var node_path: []const u8 = "node"; // default to "node" in PATH
    var output_path: ?[]const u8 = null;
    var dep_file_path: ?[]const u8 = null;
    const runner_script = @embedFile("builder.js");

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--node-path")) node_path = args.next() orelse return error.MissingNodePath;
        if (std.mem.eql(u8, arg, "--bun-path")) node_path = args.next() orelse return error.MissingNodePath;
        if (std.mem.eql(u8, arg, "--output")) output_path = args.next() orelse return error.MissingOutputPath;
        if (std.mem.eql(u8, arg, "--dep-file")) dep_file_path = args.next() orelse return error.MissingDepFilePath;
    }

    // Read stdin into memory
    var buffer: [4096]u8 = undefined;
    var reader = std.Io.File.stdin().readerStreaming(init.io, &buffer);
    var writer = std.Io.Writer.Allocating.init(allocator);
    defer writer.deinit();
    _ = try reader.interface.streamRemaining(&writer.writer);
    const input_json = try writer.toOwnedSlice();
    defer allocator.free(input_json);

    // Parse and inject output path into each build config
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, input_json, .{});
    defer parsed.deinit();

    const builds = parsed.value.array.items;
    const build_count = builds.len;

    if (output_path) |op| {
        for (builds) |*build_item| {
            const config_ptr = build_item.object.getPtr("config").?;
            try config_ptr.object.put(allocator, "output", .{ .string = op });
        }
    }

    // Re-serialize with injected output path
    const modified_json = try std.json.Stringify.valueAlloc(allocator, parsed.value, .{});
    defer allocator.free(modified_json);

    var child = try std.process.spawn(init.io, .{
        .argv = &.{ node_path, "-e", runner_script },
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .inherit,
    });

    // Best-effort cleanup if we exit before the explicit wait below.
    defer if (child.id != null) {
        _ = child.wait(init.io) catch {};
    };

    // Write config to the JS runtime's stdin, then close so it sees EOF.
    // Clear child.stdin so wait()'s cleanup doesn't double-close the handle.
    if (child.stdin) |stdin_file| {
        try stdin_file.writeStreamingAll(init.io, modified_json);
        stdin_file.close(init.io);
        child.stdin = null;
    }

    var progress = std.Progress.start(init.io, .{
        .root_name = "tailwindcss",
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
        var stdout_buffer: [4096]u8 = undefined;
        var streaming_reader = stdout_file.readerStreaming(init.io, &stdout_buffer);
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

            try std.Io.sleep(init.io, .fromMilliseconds(10), .awake);

            const name = try std.fmt.allocPrint(arena, "{s} ({d})", .{ ev.name, ev.id });

            switch (ev.type) {
                .start => {
                    const node = progress.start(name, 0);
                    try nodes.put(name, node);
                },
                .result => {
                    if (ev.success == false) failed += 1;
                    // Collect discovered dependencies for dep file
                    for (ev.dependencies) |dep| {
                        try all_deps.append(allocator, try arena.dupe(u8, dep));
                    }
                },
                .@"error" => {
                    failed += 1;
                    if (ev.@"error") |msg| {
                        std.debug.print("tailwindcss [{s}] error: {s}\n", .{ ev.name, msg });
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
        writeDepFile(allocator, init.io, dfp, output_path orelse "output.css", all_deps.items) catch |err| {
            std.debug.print("Failed to write dep file: {any}\n", .{err});
        };
    }

    const term = child.wait(init.io) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Failed to execute JS runtime: executable not found at '{s}'\n", .{node_path});
            return error.NodeNotFound;
        }
        std.debug.print("Failed to wait for JS runtime process: {any}\n", .{err});
        return error.WaitFailed;
    };
    const exit_code: u8 = switch (term) {
        .exited => |c| c,
        else => 1,
    };

    if (exit_code != 0 or failed > 0) {
        std.debug.print("tailwindcss: {d} build(s) failed\n", .{failed});
        std.process.exit(1);
    }
}

fn writeDepFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8, target: []const u8, deps: []const []const u8) !void {
    // Build dep file content in memory, then write in one shot
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
