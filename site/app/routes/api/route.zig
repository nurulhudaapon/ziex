pub fn GET(ctx: zx.RouteContext) !void {
    try ctx.socket.upgrade({});
}

pub fn Socket(ctx: zx.SocketContext) !void {
    var count: usize = 0;

    while (count < 10) : (count += 1) {
        std.Thread.sleep(1000 * std.time.ns_per_ms);
        try ctx.socket.write(
            try ctx.fmt("You said: {s}, count {d}", .{
                ctx.message,
                count,
            }),
        );
    }
}

const zx = @import("zx");
const std = @import("std");
