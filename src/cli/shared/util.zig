const BIN_DIR = "zig-out" ++ std.fs.path.sep_str ++ "bin";

/// Find the ZX executable from the bin directory
pub fn findprogram(io: std.Io, allocator: std.mem.Allocator, binpath: []const u8) !SerilizableAppMeta {
    if (!std.mem.eql(u8, binpath, "")) {
        var app_meta = try inspectProgram(io, allocator, binpath);
        // defer std.zon.parse.free(allocator, app_meta);
        // errdefer std.zon.parse.free(allocator, app_meta);
        app_meta.binpath = binpath;
        return app_meta;
    }

    var files = try std.Io.Dir.cwd().openDir(io, BIN_DIR, .{ .iterate = true });
    defer files.close(io);

    var exe_count: usize = 0;
    var it = files.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind == .file) {
            exe_count += 1;

            const full_path = try std.fs.path.join(allocator, &.{ BIN_DIR, entry.name });
            defer allocator.free(full_path);

            log.debug("Inspecting exe: {s}", .{full_path});

            var app_meta = inspectProgram(io, allocator, full_path) catch |err| switch (err) {
                error.ProgramNotFound, error.ParseZon, error.InvalidExe => continue,
                else => return err,
            };
            // defer std.zon.parse.free(allocator, app_meta);

            log.debug("Found app: {s} in {s}", .{ app_meta.version, full_path });

            app_meta.binpath = try allocator.dupe(u8, full_path);
            return app_meta;
        }
    }

    if (exe_count == 0) return error.EmptyBinDir;
    return error.ProgramNotFound;
}

pub fn inspectProgram(io: std.Io, allocator: std.mem.Allocator, binpath: []const u8) !SerilizableAppMeta {
    // The binary only prints metadata + exits when built with `-Dintrospect=true`
    // (see runtime/server/Server.zig:introspect). The dev command is responsible
    // for producing such a binary before calling this; here we just run it.
    var exe = try std.process.spawn(io, .{
        .argv = &.{binpath},
        .stdout = .pipe,
        .stderr = .ignore,
    });

    const source = if (exe.stdout) |estdout| blk: {
        var buf: [4096]u8 = undefined;
        var reader_streaming = estdout.readerStreaming(io, &buf);
        const reader = &reader_streaming.interface;
        var aw: std.Io.Writer.Allocating = .init(allocator);
        defer aw.deinit();
        _ = reader.streamRemaining(&aw.writer) catch |err| {
            exe.kill(io);
            return err;
        };
        break :blk try aw.toOwnedSlice();
    } else {
        exe.kill(io);
        return error.ProgramNotFound;
    };
    defer allocator.free(source);

    _ = exe.wait(io) catch {};

    if (source.len == 0) return error.ProgramNotFound;

    const source_z = try allocator.dupeZ(u8, source);
    defer allocator.free(source_z);

    const app_meta = try std.zon.parse.fromSliceAlloc(SerilizableAppMeta, allocator, source_z, null, .{});

    return app_meta;
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
                    try std.Io.Dir.copyFile(std.Io.Dir.cwd(), src_path, dest, std.fs.path.basename(src_path), io, .{});
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
const SerilizableAppMeta = zx.server.SerilizableAppMeta;
