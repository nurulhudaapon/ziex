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

pub fn spawnZig(io: std.Io, options: std.process.SpawnOptions) std.process.SpawnError!std.process.Child {
    return std.process.spawn(io, options) catch |err| switch (err) {
        error.FileNotFound => {
            if (options.argv.len == 0 or std.mem.eql(u8, options.argv[0], "zig")) return err;
            log.debug("zig not found at {s}, falling back to PATH", .{options.argv[0]});
            var argv_buf: [64][]const u8 = undefined;
            if (options.argv.len > argv_buf.len) return err;
            @memcpy(argv_buf[0..options.argv.len], options.argv);
            argv_buf[0] = "zig";
            var retry = options;
            retry.argv = argv_buf[0..options.argv.len];
            return std.process.spawn(io, retry);
        },
        else => return err,
    };
}

const ManifestApp = @import("../../build/Manifest.zig").App;

/// Resolve the installed app executable from `manifest/app.zon`, or `--binpath`.
pub fn resolveExePath(
    io: std.Io,
    allocator: std.mem.Allocator,
    install_prefix: []const u8,
    binpath_override: []const u8,
) ![]const u8 {
    if (binpath_override.len > 0) {
        _ = std.Io.Dir.cwd().statFile(io, binpath_override, .{}) catch return error.ExecutableNotFound;
        return try allocator.dupe(u8, binpath_override);
    }

    const manifest_path = try std.fs.path.join(allocator, &.{ install_prefix, "manifest", "app.zon" });
    defer allocator.free(manifest_path);

    const source = try std.Io.Dir.cwd().readFileAlloc(io, manifest_path, allocator, .unlimited);
    defer allocator.free(source);

    const source_z = try allocator.dupeSentinel(u8, source, 0);
    defer allocator.free(source_z);

    const manifest = try std.zon.parse.fromSliceAlloc(ManifestApp, allocator, source_z, null, .{ .ignore_unknown_fields = true });
    defer std.zon.parse.free(allocator, manifest);

    const rel = manifest.exe_path orelse return error.ExecutableNotFound;
    const path = try std.fs.path.join(allocator, &.{ install_prefix, rel });
    _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch return error.ExecutableNotFound;
    return path;
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

            const rel_base = if ((public_to_root and std.mem.eql(u8, source_dir, "public")) or
                std.mem.eql(u8, source_dir, ".")) "" else source_dir;
            const dst_rel_path = try std.fs.path.join(allocator, &.{
                rel_base,
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

pub fn randInt(io: std.Io, comptime T: type) T {
    var x: T = undefined;
    io.random(@ptrCast(&x));
    return x;
}

pub const TempDir = struct {
    const temp_dir = std.fs.path.fmtJoin(&.{ ".zig-cache", "ziex", "tmp" });
    path: []const u8,

    pub fn init(io: std.Io, allocator: std.mem.Allocator) !TempDir {
        return .{
            .path = try std.fmt.allocPrint(
                allocator,
                "{f}{s}{x}",
                .{ temp_dir, std.fs.path.sep_str, randInt(io, u32) },
            ),
        };
    }

    pub fn deinit(self: *TempDir, io: std.Io, allocator: std.mem.Allocator) void {
        std.Io.Dir.cwd().deleteTree(io, self.path) catch |err| switch (err) {
            else => log.err("failed to delete temp directory: {any}", .{err}),
        };
        allocator.free(self.path);
    }
};

pub const stdio = @import("stdio.zig");
pub const OutputMode = stdio.OutputMode;
pub const OutputTarget = stdio.OutputTarget;
pub const StreamOptions = stdio.StreamOptions;
pub const ChildOutputOptions = stdio.ChildOutputOptions;
pub const ChildOutput = stdio.ChildOutput;
pub const captureChildOutput = stdio.captureChildOutput;

const std = @import("std");
const builtin = @import("builtin");
const tui = @import("../../tui/main.zig");
const log = std.log.scoped(.cli);
