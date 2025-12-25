const std = @import("std");
const builtin = @import("builtin");

pub fn main() !void {
    var status: u8 = 0;
    for (builtin.test_functions) |t| {
        const start = std.time.nanoTimestamp();
        const result = t.func();
        const end = std.time.nanoTimestamp();
        const elapsed: i64 = @intCast(end - start);
        const name = t.name[5..];
        if (result) |_| {
            std.log.scoped(.PASS).info("{s} ({D})", .{ name, elapsed });
        } else |err| switch (err) {
            error.SkipZigTest => {
                std.log.scoped(.SKIP).info("{s}", .{
                    name,
                });
            },
            else => {
                status += 1;
                std.log.scoped(.FAIL).info("{s} - {t}", .{ name, err });
            },
        }
    }
    std.process.exit(status);
}
