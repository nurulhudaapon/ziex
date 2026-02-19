const std = @import("std");
const zx = @import("zx");
const pg = @import("Playground.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var aw = std.Io.Writer.Allocating.init(allocator);

    try pg.Playground(allocator).render(&aw.writer);
    try std.fs.File.stdout().writeAll(aw.written());
    std.debug.print("{s} {any}", .{ aw.written(), zx });
}
