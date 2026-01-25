const std = @import("std");
const zx = @import("zx");

export fn main() void {
    const allocator = std.heap.wasm_allocator;

    const ctx = zx.PageContext{
        .request = .{
            .url = "",
            .method = .GET,
            .pathname = "",
            .headers = .{},
            .arena = allocator,
        },
        .response = .{ .arena = allocator },
        .allocator = allocator,
        .arena = allocator,
    };

    const cmp = @import("pages/examples/wasm/page.zig").Page(ctx);
    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();
    cmp.render(&aw.writer) catch {};

    std.log.info("{s}", .{aw.written()});
}

pub const std_options = zx.std_options;
