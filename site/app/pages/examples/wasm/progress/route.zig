var progress: u32 = 0;
var prng = std.Random.DefaultPrng.init(0);

pub fn POST(ctx: zx.RouteContext) !void {
    const delay = prng.random().intRangeAtMost(u64, 200, 800);
    std.Thread.sleep(delay * std.time.ns_per_ms);

    const increment = prng.random().intRangeAtMost(u32, 5, 25);
    progress += increment;

    if (progress >= 100) {
        progress = 100;
    }

    const completed = progress >= 100;
    try ctx.response.json(.{
        .progress = progress,
        .increment = increment,
        .completed = completed,
    }, .{});

    if (completed) {
        progress = 0;
    }
}

const std = @import("std");
const zx = @import("zx");
