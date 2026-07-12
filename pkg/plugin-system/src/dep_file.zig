const std = @import("std");

/// Write a Make-style depfile: `target: dep1 dep2 ...`
pub fn writeDepFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    target: []const u8,
    deps: []const []const u8,
) !void {
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
