const std = @import("std");
const bunjs = @import("bunjs");

pub fn build(b: *std.Build) !void {
    const builds = try b.allocator.alloc(bunjs.Build, 3);
    for (0..3) |i| {
        builds[i] = .{
            .name = b.fmt("example-{d}", .{i}),
            .config = .{
                .entrypoints = &.{b.path("index.ts")},
                .outdir = b.path("dist"),
            },
        };
    }
    bunjs.addBuildsRun(b, builds);
}
