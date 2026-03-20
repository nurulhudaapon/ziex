const std = @import("std");
const zx = @import("zx");

pub fn build(b: *std.Build) !void {
    // --- Target and Optimize from `zig build` arguments ---
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- Options --- //
    const is_csr_bench = false;

    // --- Ziex Setup (sets up ZX, dependencies, executables and `serve` step) ---
    const site_exe = b.addExecutable(.{
        .name = "zx_bench_client",
        .root_module = b.createModule(.{
            .root_source_file = b.path("app/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{},
        }),
    });

    var zx_builder = try zx.init(b, site_exe, .{ .client = .{
        .jsglue_href = if (is_csr_bench) "assets/main.js" else null,
    } });

    zx_builder.plugin(zx.plugins.esbuild(b, .{
        .input = b.path("app/main.ts"),
        .output = zx_builder.assetsdir.path(b, "main.js"),
        .optimize = optimize,
    }));
}
