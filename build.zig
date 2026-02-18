const build_zon = @import("build.zig.zon");
const std = @import("std");

const buildlib = @import("src/build/main.zig");

// --- Public API (setting up ZX Site) --- //
/// Options for initializing
pub const ZxInitOptions = buildlib.initlib.ZxInitOptions;
/// Initialize a ZX project (sets up ZX, dependencies, executables, wasm executable and `serve` step)
pub const init = buildlib.initlib.init;

/// Default plugins
/// #### Available plugins
/// - tailwind: Tailwind CSS plugin
pub const plugins = buildlib.plugins;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- ZX Meta Options --- //
    const options = b.addOptions();
    options.addOption([]const u8, "version", build_zon.version);
    options.addOption([]const u8, "description", build_zon.description);
    options.addOption([]const u8, "repository", build_zon.repository);
    options.addOption([]const u8, "homepage", build_zon.homepage);
    options.addOption([]const u8, "minimum_zig_version", build_zon.minimum_zig_version);
    options.addOption([]const u8, "jsglue_version", build_zon.jsglue_version);

    // --- ZX App Module --- //
    const mod = b.addModule("zx", .{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize });
    const httpz_dep = b.dependency("httpz", .{ .target = target, .optimize = optimize });
    const tree_sitter_dep = b.dependency("tree_sitter", .{ .target = target, .optimize = optimize });
    const tree_sitter_zx_dep = b.dependency("tree_sitter_zx", .{ .target = target, .optimize = optimize, .@"build-shared" = false });
    const tree_sitter_mdzx_dep = b.dependency("tree_sitter_mdzx", .{ .target = target, .optimize = optimize, .@"build-shared" = false });
    const cachez_dep = b.dependency("cachez", .{ .target = target, .optimize = optimize });

    mod.addImport("cachez", cachez_dep.module("cache"));
    mod.addImport("httpz", httpz_dep.module("httpz"));
    mod.addImport("tree_sitter", tree_sitter_dep.module("tree_sitter"));
    mod.addImport("tree_sitter_zx", tree_sitter_zx_dep.module("tree_sitter_zx"));
    mod.addImport("tree_sitter_mdzx", tree_sitter_mdzx_dep.module("tree_sitter_mdzx"));
    mod.addOptions("zx_info", options);
    // Add stub meta for standalone builds (overridden in user projects with generated meta)
    // stub_meta.zig imports stub_components.zig directly from the same directory
    mod.addAnonymousImport("zx_meta", .{ .root_source_file = b.path("src/build/stub_meta.zig"), .imports = &.{.{ .name = "zx", .module = mod }} });

    // --- ZX WASM Module --- //
    const zx_wasm_mod = b.addModule("zx_wasm", .{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize });
    const jsz_dep = b.dependency("zig_js", .{ .target = target, .optimize = optimize });
    zx_wasm_mod.addImport("js", jsz_dep.module("zig-js"));
    zx_wasm_mod.addOptions("zx_info", options);
    // Add stub meta for WASM builds (overridden in user projects with generated meta)
    zx_wasm_mod.addAnonymousImport("zx_meta", .{ .root_source_file = b.path("src/build/stub_meta.zig"), .imports = &.{.{ .name = "zx", .module = zx_wasm_mod }} });

    // --- ZX CLI (Transpiler, Exporter, Dev Server) --- //
    const zli_dep = b.dependency("zli", .{ .target = target, .optimize = optimize });
    const exe_rootmod_opts: std.Build.Module.CreateOptions = .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zx", .module = mod },
            .{ .name = "zli", .module = zli_dep.module("zli") },
        },
    };
    const exe = b.addExecutable(.{ .name = "zx", .root_module = b.createModule(exe_rootmod_opts) });
    b.installArtifact(exe);

    // --- Steps: Run --- //
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    // --- ZX Site (Docs, Example, sample) --- //
    {
        const is_zx_docsite = b.option(bool, "doc", "Build the ZX docsite") orelse false;
        if (is_zx_docsite) {
            const zx_docsite_exe = b.addExecutable(.{
                .name = "zx_site",
                .root_module = b.createModule(.{
                    .root_source_file = b.path("site/main.zig"),
                    .target = target,
                    .optimize = optimize,
                }),
            });
            zx_docsite_exe.root_module.addImport("tree_sitter_zx", tree_sitter_zx_dep.module("tree_sitter_zx"));
            zx_docsite_exe.root_module.addImport("tree_sitter_mdzx", tree_sitter_mdzx_dep.module("tree_sitter_mdzx"));
            zx_docsite_exe.root_module.addImport("tree_sitter", tree_sitter_dep.module("tree_sitter"));

            var zx_build = try buildlib.initlib.initInner(b, zx_docsite_exe, exe, mod, zx_wasm_mod, .{
                .cli_path = null,
                .site_outdir = null,
                .site_path = b.path("site"),
                .copy_embedded_sources = true,
                .client = .{
                    .jsglue_href = "/assets/main.js?=" ++ build_zon.version,
                },
                .steps = .{ .serve = "serve", .dev = "dev", .@"export" = "export", .bundle = "bundle" },
                // .edge_path = b.path("site/edge.zig"),
            });

            var assetsdir = zx_build.assetsdir;

            zx_build.addPlugin(
                plugins.tailwind(b, .{
                    .bin = b.path("site/node_modules/.bin/tailwindcss"),
                    .input = b.path("site/assets/docs.css"),
                    .output = assetsdir.path(b, "docs.css"),
                    .minify = true,
                    .optimize = true,
                    .map = false,
                }),
            );
            zx_build.addPlugin(plugins.esbuild(b, .{
                .bin = b.path("site/node_modules/.bin/esbuild"),
                .input = b.path("site/scripts/react.ts"),
                .output = assetsdir.path(b, "react.js"),
                .optimize = optimize,
            }));
            zx_build.addPlugin(plugins.esbuild(b, .{
                .bin = b.path("site/node_modules/.bin/esbuild"),
                .input = b.path("site/main.ts"),
                .output = assetsdir.path(b, "main.js"),
                .optimize = optimize,
            }));
            zx_build.addPlugin(plugins.esbuild(b, .{
                .bin = b.path("site/node_modules/.bin/esbuild"),
                .input = b.path("site/scripts/docs.ts"),
                .output = assetsdir.path(b, "docs.js"),
                .optimize = optimize,
            }));

            zx_build.addPlugin(plugins.Bun.init(.{
                .build = b,
                .options = .{
                    .inputs = &.{
                        b.path("site/pages/playground/scripts/editor.ts"),
                        b.path("site/pages/playground/scripts/workers/runner.ts"),
                        b.path("site/pages/playground/scripts/workers/zig.ts"),
                        b.path("site/pages/playground/scripts/workers/zls.ts"),
                    },
                    .outdir = assetsdir.path(b, "playground/"),
                },
            }));
            // zx_b.step("serve", .serve);
        }
    }

    // --- Steps: Test --- //
    {
        const mod_tests = b.addTest(.{ .root_module = mod });
        const run_mod_tests = b.addRunArtifact(mod_tests);

        const exe_tests = b.addTest(.{ .root_module = exe.root_module });
        const run_exe_tests = b.addRunArtifact(exe_tests);

        const testing_mod = b.createModule(.{
            .root_source_file = b.path("test/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zx", .module = mod },
            },
        });
        const testing_mod_tests = b.addTest(.{
            .root_module = testing_mod,
            .test_runner = .{ .path = b.path("test/runner.zig"), .mode = .simple },
        });
        const test_run = b.addRunArtifact(testing_mod_tests);
        test_run.step.dependOn(b.getInstallStep());

        const test_step = b.step("test", "Run tests");
        test_step.dependOn(&run_mod_tests.step);
        test_step.dependOn(&run_exe_tests.step);
        test_step.dependOn(&test_run.step);
    }

    // --- ZX Releases (Cross-compilation targets for all platforms) --- //
    {
        const release_targets = [_]struct {
            name: []const u8,
            target: std.Target.Query,
        }{
            .{ .name = "linux-x64", .target = .{ .cpu_arch = .x86_64, .os_tag = .linux } },
            .{ .name = "linux-aarch64", .target = .{ .cpu_arch = .aarch64, .os_tag = .linux } },
            .{ .name = "macos-x64", .target = .{ .cpu_arch = .x86_64, .os_tag = .macos } },
            .{ .name = "macos-aarch64", .target = .{ .cpu_arch = .aarch64, .os_tag = .macos } },
            .{ .name = "windows-x64", .target = .{ .cpu_arch = .x86_64, .os_tag = .windows } },
            .{ .name = "windows-aarch64", .target = .{ .cpu_arch = .aarch64, .os_tag = .windows } },
        };

        const release_step = b.step("release", "Build release binaries for all targets");

        for (release_targets) |release_target| {
            const resolved_target = b.resolveTargetQuery(release_target.target);

            const release_tree_sitter_dep = b.dependency("tree_sitter", .{ .target = resolved_target, .optimize = .ReleaseSafe });
            const release_tree_sitter_zx_dep = b.dependency("tree_sitter_zx", .{ .target = resolved_target, .optimize = .ReleaseSafe, .@"build-shared" = false });
            const release_tree_sitter_mdzx_dep = b.dependency("tree_sitter_mdzx", .{ .target = resolved_target, .optimize = .ReleaseSafe, .@"build-shared" = false });
            const release_mod = b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = resolved_target, .optimize = .ReleaseSafe });

            release_mod.addImport("httpz", httpz_dep.module("httpz"));
            release_mod.addImport("tree_sitter", release_tree_sitter_dep.module("tree_sitter"));
            release_mod.addImport("tree_sitter_zx", release_tree_sitter_zx_dep.module("tree_sitter_zx"));
            release_mod.addImport("tree_sitter_mdzx", release_tree_sitter_mdzx_dep.module("tree_sitter_mdzx"));
            release_mod.addImport("cachez", cachez_dep.module("cache"));
            release_mod.addOptions("zx_info", options);

            const release_exe = b.addExecutable(.{
                .name = "zx",
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/main.zig"),
                    .target = resolved_target,
                    .optimize = .ReleaseSafe,
                    .imports = &.{
                        .{ .name = "zx", .module = release_mod },
                        .{ .name = "zli", .module = zli_dep.module("zli") },
                    },
                }),
            });

            const exe_ext = if (resolved_target.result.os.tag == .windows) ".exe" else "";
            const install_release = b.addInstallArtifact(release_exe, .{
                .dest_sub_path = b.fmt("release/zx-{s}{s}", .{ release_target.name, exe_ext }),
            });

            const target_step = b.step(
                b.fmt("release-{s}", .{release_target.name}),
                b.fmt("Build release binary for {s}", .{release_target.name}),
            );
            target_step.dependOn(&install_release.step);
            release_step.dependOn(&install_release.step);
        }
    }
}
