const std = @import("std");

pub fn build(b: *std.Build) void {
    // WASM target for playground artifacts
    const wasm_target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .wasi });
    const wasm_optimize: std.builtin.OptimizeMode = .ReleaseSmall;

    // Dependencies
    const pg_dep = b.dependency("playground", .{});
    const zls_dep = pg_dep.builder.dependency("zls", .{ .target = wasm_target, .optimize = wasm_optimize });
    const zx_dep = b.dependency("zx", .{ .target = wasm_target, .optimize = wasm_optimize });
    const zig_dep = pg_dep.builder.dependency("zig", .{
        .target = wasm_target,
        .optimize = wasm_optimize,
        .@"version-string" = @as([]const u8, "0.15.1"),
        .@"no-lib" = true,
        .dev = "wasm",
    });

    // Executables
    const zx_exe = zx_dep.artifact("zx");
    const zls_exe = b.addExecutable(.{
        .name = "zls",
        .root_module = b.createModule(.{
            .root_source_file = pg_dep.path("src/zls.zig"),
            .target = wasm_target,
            .optimize = wasm_optimize,
            .imports = &.{
                .{ .name = "zls", .module = zls_dep.module("zls") },
            },
        }),
    });
    zls_exe.entry = .disabled;
    zls_exe.rdynamic = true;
    const zig_exe = zig_dep.artifact("zig");

    // -- zig.tar.gz
    const run_tar = b.addSystemCommand(&.{ "tar", "-czf" });
    const zig_tar_gz = run_tar.addOutputFileArg("zig.tar.gz");
    run_tar.addArg("-C");
    run_tar.addDirectoryArg(zig_dep.path("."));
    run_tar.addArg("lib/std");

    // -- zx.tar.gz
    const run_zx_tar = b.addSystemCommand(&.{ "tar", "-czf" });
    const zx_tar_gz = run_zx_tar.addOutputFileArg("zx.tar.gz");
    run_zx_tar.addArg("-C");
    run_zx_tar.addDirectoryArg(zx_dep.path("."));
    run_zx_tar.addArg("src");

    // All assets for the playground
    const playground_assets = b.addNamedWriteFiles("playground_assets");
    _ = playground_assets.addCopyFile(zls_exe.getEmittedBin(), "zls.wasm");
    _ = playground_assets.addCopyFile(zig_exe.getEmittedBin(), "zig.wasm");
    _ = playground_assets.addCopyFile(zx_exe.getEmittedBin(), "zx.wasm");
    _ = playground_assets.addCopyFile(zig_tar_gz, "zig.tar.gz");
    _ = playground_assets.addCopyFile(zx_tar_gz, "zx.tar.gz");

    // Install artifacts locally (for standalone builds)
    // b.getInstallStep().dependOn(&b.addInstallArtifact(zls_exe, .{}).step);
    // b.getInstallStep().dependOn(&b.addInstallArtifact(zig_exe, .{}).step);
    // b.getInstallStep().dependOn(&b.addInstallArtifact(zx_exe, .{}).step);
    // b.getInstallStep().dependOn(&b.addInstallFile(zig_tar_gz, "zig.tar.gz").step);
    // b.getInstallStep().dependOn(&b.addInstallFile(zx_tar_gz, "zx.tar.gz").step);

    // Install in the site/assets/playground directory for the web playground to consume
    b.getInstallStep().dependOn(&b.addInstallDirectory(.{
        .source_dir = playground_assets.getDirectory(),
        .install_dir = .{ .custom = "../../../site/assets/playground" },
        .install_subdir = "",
    }).step);
}
