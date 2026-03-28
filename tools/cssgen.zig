const std = @import("std");
const css = @import("codegen/css.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try css.writeFile(allocator, "src/style/generated.zig");
    std.debug.print("Successfully generated src/style/generated.zig using AST-Driven engine.\n", .{});
}
