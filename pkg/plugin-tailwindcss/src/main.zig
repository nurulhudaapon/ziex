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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

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

    const input_json = try std.fs.File.stdin().readToEndAlloc(allocator, 64 * 1024 * 1024);
    defer allocator.free(input_json);

    // Parse and inject output path into each build config
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, input_json, .{});
    defer parsed.deinit();

    const builds = parsed.value.array.items;
    const build_count = builds.len;

    if (output_path) |op| {
        for (builds) |*build_item| {
            const config_ptr = build_item.object.getPtr("config").?;
            try config_ptr.object.put("output", .{ .string = op });
        }
    }

    // Re-serialize with injected output path
    const modified_json = try std.json.Stringify.valueAlloc(allocator, parsed.value, .{});
    defer allocator.free(modified_json);

    var child = std.process.Child.init(
        &.{ node_path, "-e", runner_script },
        allocator,
    );

    // Node warns when both NO_COLOR and FORCE_COLOR are set.
    const env_map = try allocator.create(std.process.EnvMap);
    env_map.* = try std.process.getEnvMap(allocator);
    errdefer {
        env_map.deinit();
        allocator.destroy(env_map);
    }
    _ = env_map.remove("NO_COLOR");

    child.env_map = env_map;
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Inherit;
    try child.spawn();
    defer {
        env_map.deinit();
        allocator.destroy(env_map);
    }

    // Write config to the JS runtime's stdin, then close so it sees EOF
    try child.stdin.?.writeAll(modified_json);
    child.stdin.?.close();
    child.stdin = null;

    var progress = std.Progress.start(.{
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

        std.Thread.sleep(10 * std.time.ns_per_ms);

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

    // Write dep file before potential exit(1)
    if (dep_file_path) |dfp| {
        writeDepFile(allocator, dfp, output_path orelse "output.css", all_deps.items) catch |err| {
            std.debug.print("Failed to write dep file: {any}\n", .{err});
        };
    }

    const term = child.wait() catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Failed to execute JS runtime: executable not found at '{s}'\n", .{node_path});
            return error.NodeNotFound;
        }
        std.debug.print("Failed to wait for JS runtime process: {any}\n", .{err});
        return error.WaitFailed;
    };
    const exit_code: u8 = switch (term) {
        .Exited => |c| c,
        else => 1,
    };

    if (exit_code != 0 or failed > 0) {
        std.debug.print("tailwindcss: {d} build(s) failed\n", .{failed});
        std.process.exit(1);
    }
}

fn writeDepFile(allocator: std.mem.Allocator, path: []const u8, target: []const u8, deps: []const []const u8) !void {
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
    const f = try std.fs.cwd().createFile(path, .{});
    defer f.close();
    try f.writeAll(buf.items);
}
