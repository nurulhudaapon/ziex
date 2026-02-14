const std = @import("std");
const zx = @import("zx");

const Platform = enum {
    chromium,
    firefox,
    development,
};

pub fn build(b: *std.Build) !void {
    // --- Target and Optimize from `zig build` arguments ---
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const build_options = b.addOptions();
    const platform = b.option(Platform, "platform", "Platform to build for");
    build_options.addOption(Platform, "platform", platform orelse .development);

    // --- ZX Setup (sets up ZX, dependencies, executables and `serve` step) ---
    const site_exe = b.addExecutable(.{
        .name = "zx_site",
        .root_module = b.createModule(.{
            .root_source_file = b.path("app/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{},
        }),
    });

    site_exe.root_module.addOptions("build_options", build_options);
    _ = try zx.init(b, site_exe, .{});
}
