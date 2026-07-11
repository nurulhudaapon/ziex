const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const allocator = gpa.allocator();

    // --- Flags --- //
    var esbuild_path: []const u8 = "node_modules/.bin/esbuild";
    var outdir_path: ?[]const u8 = null;
    var dep_file_path: ?[]const u8 = null;

    var args = try init.minimal.args.iterateAllocator(allocator);
    defer args.deinit();
    _ = args.next(); // skip program name

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--esbuild-path")) esbuild_path = args.next() orelse return error.MissingEsbuildPath;
        if (std.mem.eql(u8, arg, "--outdir")) outdir_path = args.next() orelse return error.MissingOutdirPath;
        if (std.mem.eql(u8, arg, "--dep-file")) dep_file_path = args.next() orelse return error.MissingDepFilePath;
    }

    const outdir = outdir_path orelse "dist";

    // Read stdin into memory
    var stdin_buffer: [4096]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(init.io, &stdin_buffer);
    var stdin_writer = std.Io.Writer.Allocating.init(allocator);
    defer stdin_writer.deinit();
    _ = try stdin_reader.interface.streamRemaining(&stdin_writer.writer);
    const input_json = try stdin_writer.toOwnedSlice();
    defer allocator.free(input_json);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, input_json, .{});
    defer parsed.deinit();

    const builds = parsed.value.array.items;
    const build_count = builds.len;

    var progress = std.Progress.start(init.io, .{
        .root_name = "esbuild",
        .estimated_total_items = build_count,
    });
    defer progress.end();

    var all_deps = std.ArrayList([]const u8).empty;
    defer all_deps.deinit(allocator);

    var failed: usize = 0;

    for (builds, 0..) |build_item, i| {
        const name = if (build_item.object.get("name")) |n| n.string else "esbuild";
        const id: u32 = if (build_item.object.get("id")) |id_val| switch (id_val) {
            .integer => |n| @intCast(n),
            else => @intCast(i),
        } else @intCast(i);
        const config = build_item.object.get("config") orelse return error.MissingConfig;

        const display = try std.fmt.allocPrint(allocator, "{s} ({d})", .{ name, id });
        const node = progress.start(display, 0);
        defer {
            node.end();
            progress.completeOne();
        }

        const meta_path = try std.fmt.allocPrint(allocator, "{s}/.esbuild-meta-{d}.json", .{ outdir, id });

        const argv = try buildEsbuildArgv(allocator, esbuild_path, config, outdir, meta_path);
        defer allocator.free(argv);

        var child = std.process.spawn(init.io, .{
            .argv = argv,
            .stdin = .ignore,
            .stdout = .inherit,
            .stderr = .inherit,
        }) catch |err| {
            if (err == error.FileNotFound) {
                std.debug.print("Failed to execute esbuild: executable not found at '{s}'\n", .{esbuild_path});
                return error.EsbuildNotFound;
            }
            return err;
        };

        const term = child.wait(init.io) catch |err| {
            std.debug.print("Failed to wait for esbuild process: {any}\n", .{err});
            return error.WaitFailed;
        };
        const exit_code: u8 = switch (term) {
            .exited => |c| c,
            else => 1,
        };

        if (exit_code != 0) {
            failed += 1;
            std.debug.print("esbuild [{s}] failed with exit code {d}\n", .{ name, exit_code });
            continue;
        }

        collectMetafileDeps(allocator, init.io, meta_path, &all_deps) catch |err| {
            std.debug.print("esbuild [{s}] warning: failed to read metafile: {any}\n", .{ name, err });
        };
        std.Io.Dir.cwd().deleteFile(init.io, meta_path) catch {};
    }

    if (dep_file_path) |dfp| {
        writeDepFile(allocator, init.io, dfp, outdir, all_deps.items) catch |err| {
            std.debug.print("Failed to write dep file: {any}\n", .{err});
        };
    }

    if (failed > 0) {
        std.debug.print("esbuild: {d} build(s) failed\n", .{failed});
        std.process.exit(1);
    }
}

fn buildEsbuildArgv(
    allocator: std.mem.Allocator,
    esbuild_bin: []const u8,
    config: std.json.Value,
    outdir: []const u8,
    meta_path: []const u8,
) ![]const []const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    errdefer argv.deinit(allocator);

    try argv.append(allocator, esbuild_bin);

    const entrypoints = config.object.get("entrypoints") orelse return error.MissingEntrypoints;
    for (entrypoints.array.items) |ep| {
        try argv.append(allocator, ep.string);
    }

    // Bundle defaults to true (matches previous JS runner behavior).
    const bundle = if (config.object.get("bundle")) |v| v.bool else true;
    if (bundle) try argv.append(allocator, "--bundle");

    try argv.append(allocator, try std.fmt.allocPrint(allocator, "--outdir={s}", .{outdir}));
    try argv.append(allocator, try std.fmt.allocPrint(allocator, "--metafile={s}", .{meta_path}));
    try argv.append(allocator, "--log-level=error");

    if (config.object.get("platform")) |v| {
        try argv.append(allocator, try std.fmt.allocPrint(allocator, "--platform={s}", .{v.string}));
    }
    if (config.object.get("format")) |v| {
        try argv.append(allocator, try std.fmt.allocPrint(allocator, "--format={s}", .{v.string}));
    }
    if (config.object.get("minify")) |v| {
        if (v.bool) try argv.append(allocator, "--minify");
    }
    if (config.object.get("splitting")) |v| {
        if (v.bool) try argv.append(allocator, "--splitting");
    }
    if (config.object.get("publicPath")) |v| {
        try argv.append(allocator, try std.fmt.allocPrint(allocator, "--public-path={s}", .{v.string}));
    }
    if (config.object.get("sourcemap")) |v| {
        const sm = v.string;
        if (!std.mem.eql(u8, sm, "none")) {
            try argv.append(allocator, try std.fmt.allocPrint(allocator, "--sourcemap={s}", .{sm}));
        }
    }
    if (config.object.get("external")) |v| {
        for (v.array.items) |ext| {
            try argv.append(allocator, try std.fmt.allocPrint(allocator, "--external:{s}", .{ext.string}));
        }
    }
    if (config.object.get("target")) |v| {
        if (v.array.items.len > 0) {
            var targets: std.ArrayList(u8) = .empty;
            defer targets.deinit(allocator);
            for (v.array.items, 0..) |t, i| {
                if (i > 0) try targets.append(allocator, ',');
                try targets.appendSlice(allocator, t.string);
            }
            try argv.append(allocator, try std.fmt.allocPrint(allocator, "--target={s}", .{targets.items}));
        }
    }
    if (config.object.get("define")) |v| {
        var it = v.object.iterator();
        while (it.next()) |entry| {
            try argv.append(allocator, try std.fmt.allocPrint(allocator, "--define:{s}={s}", .{ entry.key_ptr.*, entry.value_ptr.string }));
        }
    }

    return try argv.toOwnedSlice(allocator);
}

fn collectMetafileDeps(
    allocator: std.mem.Allocator,
    io: std.Io,
    meta_path: []const u8,
    all_deps: *std.ArrayList([]const u8),
) !void {
    const file = try std.Io.Dir.cwd().openFile(io, meta_path, .{});
    defer file.close(io);

    var read_buf: [4096]u8 = undefined;
    var reader = file.readerStreaming(io, &read_buf);
    var contents = std.Io.Writer.Allocating.init(allocator);
    defer contents.deinit();
    _ = try reader.interface.streamRemaining(&contents.writer);
    const json_bytes = try contents.toOwnedSlice();
    defer allocator.free(json_bytes);

    const meta = try std.json.parseFromSlice(std.json.Value, allocator, json_bytes, .{});
    defer meta.deinit();

    const inputs = meta.value.object.get("inputs") orelse return;
    var it = inputs.object.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        // Skip plugin-namespaced keys (e.g. "text-attr:/abs/path") if any appear.
        var path = key;
        if (std.mem.indexOfScalar(u8, key, ':')) |colon| {
            if (colon > 1) path = key[colon + 1 ..];
        }

        const abs = std.Io.Dir.cwd().realPathFileAlloc(io, path, allocator) catch continue;
        try all_deps.append(allocator, abs);
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
