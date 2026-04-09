const std = @import("std");
const zx = @import("zx");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const app_exe = b.addExecutable(.{
        .name = "zx_bench_client",
        .root_module = b.createModule(.{
            .root_source_file = b.path("app/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{},
        }),
    });

    var zx_builder = try zx.init(b, app_exe, .{});
    zx_builder = zx_builder;
}
