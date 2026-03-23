const std = @import("std");
const bunjs = @import("bunjs");

pub fn build(b: *std.Build) !void {
    const builds = try b.allocator.alloc(bunjs.Build, 3);
    for (0..3) |i| {
        builds[i] = .{
            .name = b.fmt("example-{d}", .{i}),
            .config = .{
                .entrypoints = &.{b.path("index.ts")},
                .target = .browser,
                .minify = b.release_mode != .off,
                .sourcemap = if (b.release_mode == .off) .@"inline" else .none,
            },
        };
    }
    const outputs = bunjs.addBuilds(b, builds);
    for (outputs, 0..) |output, i| {
        const install = b.addInstallDirectory(.{
            .source_dir = output.dir,
            .install_dir = .prefix,
            .install_subdir = b.fmt("dist-{d}", .{i}),
        });
        b.default_step.dependOn(&install.step);
    }
}
