const std = @import("std");
const playground = @import("playground_mod");

pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"}d);
    try playground.bufferedPrint();
}
