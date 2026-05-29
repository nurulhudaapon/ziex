const BIN_DIR = "zig-out" ++ std.fs.path.sep_str ++ "bin";

/// Build-time emitted metadata, written alongside the installed binary as
/// `<exe>.meta.zon`.
pub const BuildMeta = struct {
    pub const Route = struct {
        path: []const u8,
        kind: []const u8 = "Page",
        methods: []const []const u8 = &.{},
        has_notfound: bool = false,
        is_dynamic: bool = false,
    };
    pub const ServerCfg = struct {
        port: ?u16 = null,
        address: ?[]const u8 = null,
    };
    pub const Config = struct {
        server: ServerCfg = .{},
    };

    pub const CliCommand = enum { dev, serve, @"export", @"--" };

    binpath: ?[]const u8 = null,
    rootdir: ?[]const u8 = null,
    routes: []const Route = &.{},
    config: Config = .{},
    version: []const u8 = "",
    cli_command: ?CliCommand = null,

    pub fn port(self: BuildMeta) ?u16 {
        return self.config.server.port;
    }
    pub fn address(self: BuildMeta) ?[]const u8 {
        return self.config.server.address;
    }
};

/// Find the ZX app metadata from the install dir.
///
/// If `binpath` is given, looks for `<binpath>.meta.zon` next to it.
/// Otherwise scans `zig-out/bin` for any `*.meta.zon` file.
pub fn findprogram(io: std.Io, allocator: std.mem.Allocator, binpath: []const u8) !BuildMeta {
    if (!std.mem.eql(u8, binpath, "")) {
        const meta_path = try std.fmt.allocPrint(allocator, "{s}.meta.zon", .{binpath});
        defer allocator.free(meta_path);
        var meta = try readBuildMeta(io, allocator, meta_path);
        if (meta.binpath) |bp| allocator.free(bp);
        meta.binpath = try resolveBinPath(io, allocator, binpath);
        return meta;
    }

    var files = try std.Io.Dir.cwd().openDir(io, BIN_DIR, .{ .iterate = true });
    defer files.close(io);

    var entry_count: usize = 0;
    var it = files.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        entry_count += 1;
        if (!std.mem.endsWith(u8, entry.name, ".meta.zon")) continue;

        const meta_path = try std.fs.path.join(allocator, &.{ BIN_DIR, entry.name });
        defer allocator.free(meta_path);

        log.debug("Reading meta: {s}", .{meta_path});

        var meta = readBuildMeta(io, allocator, meta_path) catch |err| switch (err) {
            error.ParseZon, error.FileNotFound => continue,
            else => return err,
        };

        // Derive the binary path from the meta file path: strip ".meta.zon".
        const exe_basename = entry.name[0 .. entry.name.len - ".meta.zon".len];
        const inferred_binpath = try std.fs.path.join(allocator, &.{ BIN_DIR, exe_basename });
        defer allocator.free(inferred_binpath);
        const resolved_binpath = try resolveBinPath(io, allocator, inferred_binpath);
        if (meta.binpath) |bp| allocator.free(bp);
        meta.binpath = resolved_binpath;

        log.debug("Found app: {s} at {s}", .{ meta.version, meta.binpath.? });
        return meta;
    }

    if (entry_count == 0) return error.EmptyBinDir;
    return error.ProgramNotFound;
}

fn resolveBinPath(io: std.Io, allocator: std.mem.Allocator, binpath: []const u8) ![]const u8 {
    if (fileExists(io, binpath)) {
        return allocator.dupe(u8, binpath);
    }

    if (builtin.os.tag == .windows and !std.mem.endsWith(u8, binpath, ".exe")) {
        const exe_binpath = try std.fmt.allocPrint(allocator, "{s}.exe", .{binpath});
        if (fileExists(io, exe_binpath)) {
            return exe_binpath;
        }
        allocator.free(exe_binpath);
    }

    return allocator.dupe(u8, binpath);
}

fn fileExists(io: std.Io, path: []const u8) bool {
    _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return true;
}

fn readBuildMeta(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !BuildMeta {
    const source = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
    defer allocator.free(source);
    const source_z = try allocator.dupeZ(u8, source);
    defer allocator.free(source_z);
    return try std.zon.parse.fromSliceAlloc(BuildMeta, allocator, source_z, null, .{ .ignore_unknown_fields = true });
}

pub fn freeBuildMeta(allocator: std.mem.Allocator, meta: *BuildMeta) void {
    std.zon.parse.free(allocator, meta.*);
}

const ignore_dirs = [_][]const u8{".well-known" ++ std.fs.path.sep_str ++ "_zx"};
fn shouldIgnorePath(path: []const u8) bool {
    for (ignore_dirs) |ignore_dir| {
        if (std.mem.startsWith(u8, path, ignore_dir)) return true;
    }
    return false;
}
pub fn copydirs(
    io: std.Io,
    allocator: std.mem.Allocator,
    base_dir: []const u8,
    source_dirs: []const []const u8,
    dest_dir: []const u8,
    public_to_root: bool,
    printer: *tui.Printer,
) !void {
    for (source_dirs) |source_dir| {
        const source_path = try std.fs.path.join(allocator, &.{ base_dir, source_dir });
        defer allocator.free(source_path);

        var source = std.Io.Dir.cwd().openDir(io, source_path, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => continue,
            error.NotDir => continue,
            else => return err,
        };
        defer source.close(io);

        std.Io.Dir.cwd().createDirPath(io, dest_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        var dest = try std.Io.Dir.cwd().openDir(io, dest_dir, .{});
        defer dest.close(io);

        var walker = try source.walk(allocator);
        defer walker.deinit();

        while (try walker.next(io)) |entry| {
            const src_path = try std.fs.path.join(allocator, &.{ source_path, entry.path });
            defer allocator.free(src_path);

            const dst_rel_path = try std.fs.path.join(allocator, &.{
                if (public_to_root and std.mem.eql(u8, source_dir, "public")) "" else source_dir,
                entry.path,
            });
            defer allocator.free(dst_rel_path);

            const dst_abs_path = try std.fs.path.join(allocator, &.{ dest_dir, dst_rel_path });
            defer allocator.free(dst_abs_path);

            switch (entry.kind) {
                .file => {
                    if (shouldIgnorePath(dst_rel_path)) continue;

                    // Create parent directory if needed
                    if (std.fs.path.dirname(dst_abs_path)) |parent| {
                        std.Io.Dir.cwd().createDirPath(io, parent) catch |err| switch (err) {
                            error.PathAlreadyExists => {},
                            else => return err,
                        };
                    }

                    // Copy file
                    try std.Io.Dir.copyFile(std.Io.Dir.cwd(), src_path, dest, dst_rel_path, io, .{});
                    printer.filepath(dst_rel_path);
                },
                .directory => {
                    if (shouldIgnorePath(dst_abs_path)) continue;
                    // Create directory if needed
                    std.Io.Dir.cwd().createDirPath(io, dst_abs_path) catch |err| switch (err) {
                        error.PathAlreadyExists => {},
                        else => return err,
                    };
                },
                else => continue,
            }
        }
    }
}

pub fn getRunnablePath(io: std.Io, allocator: std.mem.Allocator, program_path: []const u8) ![]const u8 {
    if (builtin.os.tag == .windows) {
        // Create .zig-cache/tmp/.zx directory if it doesn't exist
        const cache_dir = ".zig-cache/tmp/.zx";
        try std.Io.Dir.cwd().createDirPath(io, cache_dir);

        const dest_dir = try std.Io.Dir.cwd().openDir(io, cache_dir, .{});
        defer dest_dir.close(io);
        const bin_name = std.fs.path.basename(program_path);

        // Copy the executable to the cache directory
        try std.Io.Dir.cwd().copyFile(program_path, dest_dir, bin_name, io, .{});

        const copied_program_path = try std.fs.path.join(allocator, &.{ cache_dir, bin_name });
        return copied_program_path;
    } else {
        return program_path;
    }
}

// Re-export stdio capturing functionality for backward compatibility
pub const stdio = @import("stdio.zig");
pub const OutputMode = stdio.OutputMode;
pub const OutputTarget = stdio.OutputTarget;
pub const StreamOptions = stdio.StreamOptions;
pub const ChildOutputOptions = stdio.ChildOutputOptions;
pub const ChildOutput = stdio.ChildOutput;
pub const captureChildOutput = stdio.captureChildOutput;

const std = @import("std");
const zx = @import("zx");
const builtin = @import("builtin");
const tui = @import("../../tui/main.zig");
const log = std.log.scoped(.cli);
