const build_zon = @import("build.zig.zon");
const std = @import("std");

const buildlib = @import("src/build/main.zig");

// --- Public API (setting up ZX Site) --- //
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
    options.addOption([]const u8, "version_string", build_zon.version);
    options.addOption([]const u8, "description", build_zon.description);
    options.addOption([]const u8, "repository", build_zon.repository);

    // --- ZX App Module --- //
    const mod = b.addModule("zx", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const httpz_dep = b.dependency("httpz", .{ .target = target, .optimize = optimize });
    const tree_sitter_dep = b.lazyDependency("tree_sitter", .{ .target = target, .optimize = optimize }).?;
    const tree_sitter_zx_dep = b.dependency("tree_sitter_zx", .{ .target = target, .optimize = optimize, .@"build-shared" = false });
    mod.addImport("httpz", httpz_dep.module("httpz"));
    mod.addImport("tree_sitter", tree_sitter_dep.module("tree_sitter"));
    mod.addImport("tree_sitter_zx", tree_sitter_zx_dep.module("tree_sitter_zx"));
    mod.addOptions("zx_info", options);

    // --- ZX WASM Module --- //
    const zx_wasm_mod = b.addModule("zx_wasm", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const jsz_dep = b.dependency("zig_js", .{ .target = target, .optimize = optimize });
    zx_wasm_mod.addImport("js", jsz_dep.module("zig-js"));
    zx_wasm_mod.addOptions("zx_info", options);

    // --- ZX CLI (Transpiler, Exporter, Dev Server) --- //
    // const rustlib_step = buildlib.rustlib.build(b, target, optimize);
    const zli_dep = b.dependency("zli", .{ .target = target, .optimize = optimize });
    const exe = b.addExecutable(.{
        .name = "zx",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zx", .module = mod },
                .{ .name = "zli", .module = zli_dep.module("zli") },
                .{ .name = "tree_sitter", .module = tree_sitter_dep.module("tree_sitter") },
                .{ .name = "tree_sitter_zx", .module = tree_sitter_zx_dep.module("tree_sitter_zx") },
            },
        }),
    });
    // buildlib.rustlib.link(b, exe, rustlib_step, optimize);
    b.installArtifact(exe);

    // --- Steps: Run --- //
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    // --- ZX Site (Docs, Example, sample) --- //
    {
        const is_zx_docsite = b.option(bool, "zx-docsite", "Build the ZX docsite") orelse false;
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
            zx_docsite_exe.root_module.addImport("tree_sitter", tree_sitter_dep.module("tree_sitter"));

            try buildlib.initlib.initInner(b, zx_docsite_exe, exe, mod, zx_wasm_mod, .{
                .cli_path = null,
                .site_outdir = "site/.zx",
                .site_path = "site",
                .experimental_enabled_csr = true,
                .steps = .{ .serve = "serve", .dev = "dev", .@"export" = "export", .bundle = "bundle" },
                .plugins = &.{plugins.tailwind(.{})},
            });
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
        const run_transpiler_tests = b.addRunArtifact(testing_mod_tests);

        const test_step = b.step("test", "Run tests");
        test_step.dependOn(&run_mod_tests.step);
        test_step.dependOn(&run_exe_tests.step);
        test_step.dependOn(&run_transpiler_tests.step);
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
            const release_exe = b.addExecutable(.{
                .name = "zx",
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/main.zig"),
                    .target = resolved_target,
                    .optimize = .ReleaseSafe,
                    .imports = &.{
                        .{ .name = "zx", .module = mod },
                        .{ .name = "httpz", .module = httpz_dep.module("httpz") },
                        .{ .name = "zli", .module = zli_dep.module("zli") },
                    },
                }),
            });

            // const release_rustlib_step = buildlib.rustlib.build(b, resolved_target, .ReleaseFast);
            // buildlib.rustlib.link(b, release_exe, release_rustlib_step, .ReleaseFast);

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
