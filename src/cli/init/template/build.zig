const std = @import("std");
const zx = @import("zx");

pub fn build(b: *std.Build) !void {
    // --- Target and Optimize from `zig build` arguments ---
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- Root Module ---
    const mod = b.addModule("root_mod", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // --- Site Executable ---
    const site_exe = b.addExecutable(.{
        .name = "zx_site",
        .root_module = b.createModule(.{
            .root_source_file = b.path("site/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "root_mod", .module = mod },
            },
        }),
    });

    // --- ZX setup: wires dependencies and adds `zx`/`dev` build steps ---
    _ = try zx.init(b, site_exe, .{
        .experimental = .{ .enabled_csr = true },
    });
}
