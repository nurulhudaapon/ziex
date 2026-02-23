const std = @import("std");
const zx = @import("zx");
const pg = @import("Playground.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var aw = std.Io.Writer.Allocating.init(allocator);

    if (!@hasDecl(pg, "Playground")) {
        @compileError("`pub fn Playground(allocator: zx.Allocator) zx.Component` is required");
    }

    const pg_type = @TypeOf(pg.Playground);
    const expected_type = fn (allocator: zx.Allocator) zx.Component;

    if (pg_type != expected_type) {
        @compileError("`Playground` type needs to be `fn (allocator: zx.Allocator) zx.Component`");
    }

    try pg.Playground(allocator).render(&aw.writer);
    try std.fs.File.stdout().writeAll(aw.written());
}
