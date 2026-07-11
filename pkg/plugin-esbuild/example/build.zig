const std = @import("std");
const esbuild = @import("esbuild");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const builds = try b.allocator.alloc(esbuild.Build, 3);
    for (0..3) |i| {
        builds[i] = .{
            .name = b.fmt("example-{d}", .{i}),
            .config = .{
                .entrypoints = &.{b.path("index.ts")},
                .platform = .browser,
                .minify = optimize != .Debug,
                .sourcemap = if (optimize == .Debug) .@"inline" else .none,
            },
        };
    }
    const outputs = esbuild.addBuilds(b, builds);
    for (outputs, 0..) |output, i| {
        const install = b.addInstallDirectory(.{
            .source_dir = output.dir,
            .install_dir = .prefix,
            .install_subdir = b.fmt("dist-{d}", .{i}),
        });
        b.default_step.dependOn(&install.step);
    }
}
