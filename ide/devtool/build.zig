const std = @import("std");
const ziex = @import("zx");

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
    const platform = b.option(Platform, "platform", "Platform to build for") orelse .development;
    build_options.addOption(Platform, "platform", platform);

    const exe = b.addExecutable(.{
        .name = "ziex_devtool",
        .root_module = b.createModule(.{
            .root_source_file = b.path("app/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{},
        }),
    });

    exe.root_module.addOptions("build_options", build_options);
    var ziex_b = try ziex.init(b, exe, .{
        .client = .{
            .jsglue_href = switch (platform) {
                .chromium => "/pages/assets/_/main.js",
                else => "/assets/_/main.js",
            },
            .wasm_href = switch (platform) {
                .chromium => "/pages/assets/_/main.wasm",
                else => "/assets/_/main.wasm",
            },
        },
    });
    var assetsdir = ziex_b.assetsdir;

    ziex_b.plugin(ziex.plugins.esbuild(b, .{
        .input = b.path("app/scripts/client.ts"),
        .output = assetsdir.path(b, "_/main.js"),
        .optimize = optimize,
    }));

    // Step: zig build chromium
    const chromium_step = b.step("chromium", "Build chromium extension");
    const chromium_build = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "-Dplatform=chromium" });
    const chromium_export = b.addRunArtifact(ziex_b.zx.exe);
    chromium_export.addArgs(&.{ "export", "--outdir" });
    chromium_export.addDirectoryArg(b.path("../chromium/pages"));
    chromium_export.step.dependOn(&chromium_build.step);

    const chromium_zip = b.addSystemCommand(&.{ "zip", "-r" });
    chromium_zip.setCwd(b.path("../chromium"));
    const zip_output = chromium_zip.addOutputFileArg("ziex-devtools-chromium.zip");
    chromium_zip.addArgs(&.{"."});
    chromium_zip.step.dependOn(&chromium_export.step);

    const install_zip = b.addInstallFileWithDir(zip_output, .{ .custom = "../../chromium/dist" }, "ziex-devtools-chromium.zip");
    chromium_step.dependOn(&install_zip.step);
}
