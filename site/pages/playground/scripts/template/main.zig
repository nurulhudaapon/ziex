const std = @import("std");
const mod = @import("mod.zig");

pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    try mod.bufferedPrint();
}
