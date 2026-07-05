const std = @import("std");
const ziex = @import("ziex");
const esbuild = @import("esbuild");

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
        .cli = .{ .optimize = optimize },
        .app = .{
            .base_path = switch (platform) {
                .chromium => "/pages/",
                else => null,
            },
        },
        .client = .{
            .jsglue_href = "/assets/app.js",
        },
    });
    ziex_b = ziex_b;

    const is_release = optimize != .Debug;
    const client_scripts = esbuild.addBuild(b, .{
        .name = "devtool_scripts",
        .config = .{
            .entrypoints = &.{
                b.path("app/scripts/client.ts"),
            },
            .platform = .browser,
            .minify = is_release,
            .sourcemap = if (is_release) .none else .@"inline",
            .define = &.{
                .{ .key = "__DEV__", .value = if (is_release) "false" else "true" },
                .{ .key = "process.env.NODE_ENV", .value = if (is_release) "\"production\"" else "\"development\"" },
            },
        },
    });

    const install_main_js = b.addInstallFile(client_scripts.dir.path(b, "client.js"), "static/assets/app.js");
    b.default_step.dependOn(&install_main_js.step);

    const branding_dep = b.dependency("branding", .{});
    const install_branding = b.addInstallDirectory(.{
        .source_dir = branding_dep.path("compressed"),
        .install_dir = .prefix,
        .install_subdir = "static/assets/branding",
        .include_extensions = &.{"png"},
    });
    b.default_step.dependOn(&install_branding.step);

    // Step: zig build chromium
    const chromium_step = b.step("chromium", "Build chromium extension");
    const chromium_export = b.addRunArtifact(ziex_b.cli.exe);
    chromium_export.addArgs(&.{ "export", "--build-args", "-Dplatform=chromium", "--outdir" });
    chromium_export.addDirectoryArg(b.path("../chromium/pages"));

    const chromium_zip = b.addSystemCommand(&.{ "zip", "-r" });
    chromium_zip.setCwd(b.path("../chromium"));
    const zip_output = chromium_zip.addOutputFileArg("ziex-devtools-chromium.zip");
    chromium_zip.addArgs(&.{"."});
    chromium_zip.step.dependOn(&chromium_export.step);

    const install_zip = b.addInstallFileWithDir(zip_output, .{ .custom = "../../chromium/dist" }, "ziex-devtools-chromium.zip");
    chromium_step.dependOn(&install_zip.step);
}
