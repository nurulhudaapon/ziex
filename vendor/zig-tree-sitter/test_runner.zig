const std = @import("std");
const builtin = @import("builtin");

pub fn main(init: std.process.Init) !void {
    var status: u8 = 0;
    const clock: std.Io.Clock = .awake;
    for (builtin.test_functions) |t| {
        const start = clock.now(init.io);
        const result = t.func();
        const end = clock.now(init.io);
        const elapsed = start.durationTo(end);
        const name = t.name[5..];
        if (result) |_| {
            std.log.scoped(.PASS).info("{s} ({f})", .{ name, elapsed });
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
