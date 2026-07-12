const std = @import("std");
const Options = @import("util.zig").Options;

pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const allocator = gpa.allocator();

    var tsc_path: []const u8 = undefined;
    var outdir_path: ?[]const u8 = null;
    var dep_file_path: ?[]const u8 = null;
    var project_path: ?[]const u8 = null;
    var name: []const u8 = "typescript";
    var input_paths: std.ArrayList([]const u8) = .empty;

    var args = try init.minimal.args.iterateAllocator(allocator);
    defer args.deinit();
    _ = args.next(); // skip program name

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--tsc-path")) {
            tsc_path = args.next() orelse return error.MissingTscPath;
        } else if (std.mem.eql(u8, arg, "--outdir")) {
            outdir_path = args.next() orelse return error.MissingOutdirPath;
        } else if (std.mem.eql(u8, arg, "--dep-file")) {
            dep_file_path = args.next() orelse return error.MissingDepFilePath;
        } else if (std.mem.eql(u8, arg, "--project")) {
            project_path = args.next() orelse return error.MissingProjectPath;
        } else if (std.mem.eql(u8, arg, "--name")) {
            name = args.next() orelse return error.MissingName;
        } else if (std.mem.eql(u8, arg, "--input")) {
            try input_paths.append(allocator, args.next() orelse return error.MissingInput);
        }
    }

    const outdir = outdir_path orelse "dist";

    // Read stdin Options JSON
    var stdin_buffer: [4096]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(init.io, &stdin_buffer);
    var stdin_writer = std.Io.Writer.Allocating.init(allocator);
    defer stdin_writer.deinit();
    _ = try stdin_reader.interface.streamRemaining(&stdin_writer.writer);
    const input_json = try stdin_writer.toOwnedSlice();
    defer allocator.free(input_json);

    const options_json = if (input_json.len == 0) "{}" else input_json;
    const parsed = try std.json.parseFromSlice(Options, allocator, options_json, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    const opts = parsed.value;

    var progress = std.Progress.start(init.io, .{
        .root_name = "typescript",
        .estimated_total_items = 1,
    });
    defer progress.end();

    const node = progress.start(name, 0);
    defer {
        node.end();
        progress.completeOne();
    }

    const argv = try buildTscArgv(allocator, tsc_path, project_path, opts, outdir);
    defer allocator.free(argv);

    var child = std.process.spawn(init.io, .{
        .argv = argv,
        .stdin = .ignore,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Failed to execute tsc: executable not found at '{s}'\n", .{tsc_path});
            return error.TscNotFound;
        }
        return err;
    };

    const term = child.wait(init.io) catch |err| {
        std.debug.print("Failed to wait for tsc process: {any}\n", .{err});
        return error.WaitFailed;
    };
    const exit_code: u8 = switch (term) {
        .exited => |c| c,
        else => 1,
    };

    if (exit_code != 0) {
        std.debug.print("tsc [{s}] failed with exit code {d}\n", .{ name, exit_code });
        std.process.exit(1);
    }

    if (dep_file_path) |dfp| {
        var deps: std.ArrayList([]const u8) = .empty;
        defer deps.deinit(allocator);
        if (project_path) |pp| {
            const abs = std.Io.Dir.cwd().realPathFileAlloc(init.io, pp, allocator) catch pp;
            try deps.append(allocator, abs);
        }
        for (input_paths.items) |ip| {
            const abs = std.Io.Dir.cwd().realPathFileAlloc(init.io, ip, allocator) catch ip;
            try deps.append(allocator, abs);
        }
        writeDepFile(allocator, init.io, dfp, outdir, deps.items) catch |err| {
            std.debug.print("Failed to write dep file: {any}\n", .{err});
        };
    }
}

fn buildTscArgv(
    allocator: std.mem.Allocator,
    tsc_bin: []const u8,
    project: ?[]const u8,
    opts: Options,
    outdir: []const u8,
) ![]const []const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    errdefer argv.deinit(allocator);

    try argv.append(allocator, tsc_bin);

    if (project) |p| {
        try argv.append(allocator, "--project");
        try argv.append(allocator, p);
    }

    try argv.append(allocator, "--outDir");
    try argv.append(allocator, outdir);

    if (opts.declaration) |v| {
        try argv.append(allocator, "--declaration");
        try argv.append(allocator, if (v) "true" else "false");
    }
    if (opts.emit_declaration_only) |v| {
        if (v) try argv.append(allocator, "--emitDeclarationOnly");
    }
    if (opts.no_emit) |v| {
        if (v) try argv.append(allocator, "--noEmit");
    }
    for (opts.extra_args) |arg| {
        try argv.append(allocator, arg);
    }

    return try argv.toOwnedSlice(allocator);
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
