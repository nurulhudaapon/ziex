const std = @import("std");
const zx = @import("zx");
const mod = @import("mod.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var aw = std.Io.Writer.Allocating.init(allocator);

    try mod.Page(allocator).render(&aw.writer);
    try std.fs.File.stdout().writeAll(aw.written());
    std.debug.print("{s} {any}", .{ aw.written(), zx });
}
