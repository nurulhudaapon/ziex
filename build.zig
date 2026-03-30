const build_zon = @import("build.zig.zon");
const std = @import("std");

const buildlib = @import("src/build/main.zig");

// --- Public API (setting up ZX Site) --- //
/// Options for initializing
pub const InitOptions = buildlib.initlib.InitOptions;
/// Initialize a ZX project (sets up ZX, dependencies, executables, wasm executable and `serve` step)
pub const init = buildlib.initlib.init;

/// Default plugins
/// #### Available plugins
/// - tailwind: Tailwind CSS plugin
pub const plugins = buildlib.plugins;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exclude_lsp = b.option(bool, "exclude-lsp", "Exclude the LSP server to speed up builds") orelse false;
    const exclude_core_lang = b.option(bool, "exclude-core-lang", "Exclude core language tools (Ast/Parse/sourcemap) — only needed by CLI") orelse false;
    const exclude_db = b.option(bool, "exclude-db", "Exclude database adapter to speed up builds") orelse false;
    const is_client = b.option(bool, "is-client", "Building for the browser (client)") orelse false;
    const is_edge = b.option(bool, "is-edge", "Building for a WASI-based edge runtime") orelse false;

    // Options
    const options = b.addOptions();
    options.addOption([]const u8, "version", build_zon.version);
    options.addOption([]const u8, "description", build_zon.description);
    options.addOption([]const u8, "repository", build_zon.repository);
    options.addOption([]const u8, "homepage", build_zon.homepage);
    options.addOption([]const u8, "minimum_zig_version", build_zon.minimum_zig_version);

    const zx_runtime_options = b.addOptions();
    zx_runtime_options.addOption([]const u8, "staticdir", "zig-out/static");
    zx_runtime_options.addOption([]const u8, "datadir", "zig-out/data");

    const cli_options_dev = b.addOptions();
    cli_options_dev.addOption([]const u8, "zig_exe", b.graph.zig_exe);

    // Dependencies
    const httpz_dep = b.dependency("httpz", .{ .target = target, .optimize = optimize });
    const tree_sitter_dep = b.dependency("tree_sitter", .{ .target = target, .optimize = optimize });
    const tree_sitter_zx_dep = b.dependency("tree_sitter_zx", .{ .target = target, .optimize = optimize, .@"build-shared" = false });
    const tree_sitter_mdzx_dep = b.dependency("tree_sitter_mdzx", .{ .target = target, .optimize = optimize, .@"build-shared" = false });
    const cachez_dep = b.dependency("cachez", .{ .target = target, .optimize = optimize });
    const adapters_dep = b.dependency("adapters", .{ .target = target, .optimize = optimize });

    // --- Sub-modules (cached independently) --- //

    // Style module (35K lines, zero internal deps — cached after first compile)
    const zx_style_mod = b.addModule("zx_style", .{ .root_source_file = b.path("src/style/root.zig"), .target = target, .optimize = optimize });

    // Core language module (Ast, Parse, sourcemap — only compiled when referenced)
    const zx_core_lang_mod = b.addModule("zx_core_lang", .{ .root_source_file = b.path("src/core/root.zig"), .target = target, .optimize = optimize });
    zx_core_lang_mod.addImport("tree_sitter", tree_sitter_dep.module("tree_sitter"));
    zx_core_lang_mod.addImport("tree_sitter_zx", tree_sitter_zx_dep.module("tree_sitter_zx"));
    zx_core_lang_mod.addImport("tree_sitter_mdzx", tree_sitter_mdzx_dep.module("tree_sitter_mdzx"));

    // --- Main ZX Module --- //
    const mod = b.addModule("zx", .{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize });

    // Module feature flags (controls what gets compiled)
    const zx_module_options = b.addOptions();
    zx_module_options.addOption(bool, "exclude_core_lang", exclude_core_lang);
    zx_module_options.addOption(bool, "exclude_db", exclude_db);
    zx_module_options.addOption(bool, "is_client", is_client);
    zx_module_options.addOption(bool, "is_edge", is_edge);

    // Imports (zx)
    {
        if (!is_client) {
            mod.addImport("db", adapters_dep.module("db"));
            mod.addImport("db_sqlite", adapters_dep.module("db_sqlite"));
            mod.addImport("cachez", cachez_dep.module("cache"));
            mod.addImport("httpz", httpz_dep.module("httpz"));
        }

        if (is_client) {
            const jsz_dep = b.dependency("zig_js", .{ .target = target, .optimize = optimize });
            mod.addImport("js", jsz_dep.module("zig-js"));
        }

        if (!exclude_core_lang) mod.addImport("zx_core_lang", zx_core_lang_mod);
        mod.addImport("zx_style", zx_style_mod);
        mod.addOptions("zx_info", options);
        mod.addOptions("zx_options", zx_runtime_options);
        mod.addOptions("zx_module_options", zx_module_options);

        // Stubs
        mod.addAnonymousImport("zx_meta", .{ .root_source_file = b.path("src/build/stub_meta.zig"), .imports = &.{.{ .name = "zx", .module = mod }} });
        mod.addAnonymousImport("zx_injections", .{ .root_source_file = b.path("src/build/stubs/injections.zig") });
    }
    // --- ZX CLI (Transpiler, Exporter, Dev Server) --- //
    const zli_dep = b.dependency("zli", .{ .target = target, .optimize = optimize });
    const zls_dep = b.dependency("zls", .{ .target = target, .optimize = optimize });
    const exe_rootmod_opts: std.Build.Module.CreateOptions = .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "cli_options", .module = cli_options_dev.createModule() },
            .{ .name = "zx", .module = mod },
            .{ .name = "zli", .module = zli_dep.module("zli") },
            .{ .name = "tree_sitter", .module = tree_sitter_dep.module("tree_sitter") },
            .{ .name = "tree_sitter_zx", .module = tree_sitter_zx_dep.module("tree_sitter_zx") },
        },
    };

    const exe_build_options = b.addOptions();
    exe_build_options.addOption(bool, "exclude_lsp", exclude_lsp);

    const exe = b.addExecutable(.{ .name = "zx", .root_module = b.createModule(exe_rootmod_opts) });
    exe.root_module.addOptions("build_options", exe_build_options);
    if (!exclude_lsp) exe.root_module.addImport("zls", zls_dep.module("zls"));
    b.installArtifact(exe);

    // --- Steps: Run --- //
    {
        const run_step = b.step("run", "Run the app");
        const run_cmd = b.addRunArtifact(exe);
        run_step.dependOn(&run_cmd.step);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| run_cmd.addArgs(args);
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
                .{ .name = "cli_options", .module = cli_options_dev.createModule() },
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

        const transpile_only = b.addExecutable(.{
            .name = "transpile-only",
            .root_module = b.createModule(.{
                .root_source_file = b.path("test/transpile_only.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "zx", .module = mod },
                },
            }),
        });
        const run_transpile_only = b.addRunArtifact(transpile_only);
        const transpile_only_step = b.step("transpile-only", "Update snapshots without running full tests");
        transpile_only_step.dependOn(&run_transpile_only.step);
    }

    // --- Steps: Dev (Runs dev step for site/) --- //
    {
        const dev_step = b.step("dev", "Run the site in development mode");
        const dev_cmd = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "dev" });
        dev_cmd.setCwd(b.path("site"));
        dev_step.dependOn(&dev_cmd.step);
        if (b.args) |args| dev_cmd.addArgs(args);
    }

    // --- Steps: Site (Runs build step for site/) --- //
    {
        const site_step = b.step("site", "Build the site");
        const site_cmd = b.addSystemCommand(&.{ b.graph.zig_exe, "build" });
        site_cmd.setCwd(b.path("site"));
        site_step.dependOn(&site_cmd.step);
        if (b.args) |args| site_cmd.addArgs(args);
    }

    // --- Steps: CSS Generator --- //
    {
        const css_gen_step = b.step("cssgen", "Generate CSS types from webref");

        const css_gen_exe = b.addExecutable(.{
            .name = "cssgen",
            .root_module = b.createModule(.{
                .root_source_file = b.path("tools/codegen/css.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        const css_gen_run = b.addRunArtifact(css_gen_exe);

        if (std.fs.cwd().access("vendor/webref", .{})) |_| {} else |_| {
            const sync_cmd = b.addSystemCommand(&.{ "./tools/syncvendor", "webref" });
            css_gen_run.step.dependOn(&sync_cmd.step);
        }

        css_gen_step.dependOn(&css_gen_run.step);
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

        // --- ZX CLI Options (Release) --- //
        const cli_options_rel = b.addOptions();
        cli_options_rel.addOption([]const u8, "zig_exe", "zig");

        for (release_targets) |release_target| {
            const resolved_target = b.resolveTargetQuery(release_target.target);

            const release_tree_sitter_dep = b.dependency("tree_sitter", .{ .target = resolved_target, .optimize = .ReleaseSafe });
            const release_tree_sitter_zx_dep = b.dependency("tree_sitter_zx", .{ .target = resolved_target, .optimize = .ReleaseSafe, .@"build-shared" = false });
            const release_tree_sitter_mdzx_dep = b.dependency("tree_sitter_mdzx", .{ .target = resolved_target, .optimize = .ReleaseSafe, .@"build-shared" = false });
            const release_zls_dep = b.dependency("zls", .{ .target = resolved_target, .optimize = .ReleaseSafe });

            // Sub-modules for release
            const release_style_mod = b.createModule(.{ .root_source_file = b.path("src/style/root.zig"), .target = resolved_target, .optimize = .ReleaseSafe });
            const release_core_lang_mod = b.createModule(.{ .root_source_file = b.path("src/core/root.zig"), .target = resolved_target, .optimize = .ReleaseSafe });
            release_core_lang_mod.addImport("tree_sitter", release_tree_sitter_dep.module("tree_sitter"));
            release_core_lang_mod.addImport("tree_sitter_zx", release_tree_sitter_zx_dep.module("tree_sitter_zx"));
            release_core_lang_mod.addImport("tree_sitter_mdzx", release_tree_sitter_mdzx_dep.module("tree_sitter_mdzx"));

            const release_mod = b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = resolved_target, .optimize = .ReleaseSafe });

            // Release module options (CLI needs core_lang)
            const release_module_options = b.addOptions();
            release_module_options.addOption(bool, "exclude_core_lang", false);
            release_module_options.addOption(bool, "exclude_db", false);

            release_mod.addImport("httpz", httpz_dep.module("httpz"));
            release_mod.addImport("zx_style", release_style_mod);
            release_mod.addImport("zx_core_lang", release_core_lang_mod);
            release_mod.addOptions("zx_info", options);
            release_mod.addOptions("zx_options", zx_runtime_options);
            release_mod.addOptions("zx_module_options", release_module_options);

            const release_exe = b.addExecutable(.{
                .name = "zx",
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/main.zig"),
                    .target = resolved_target,
                    .optimize = .ReleaseSafe,
                    .imports = &.{
                        .{ .name = "cli_options", .module = cli_options_rel.createModule() },
                        .{ .name = "zx", .module = release_mod },
                        .{ .name = "zli", .module = zli_dep.module("zli") },
                        .{ .name = "zls", .module = release_zls_dep.module("zls") },
                        .{ .name = "tree_sitter", .module = release_tree_sitter_dep.module("tree_sitter") },
                        .{ .name = "tree_sitter_zx", .module = release_tree_sitter_zx_dep.module("tree_sitter_zx") },
                    },
                }),
            });
            const release_exe_build_options = b.addOptions();
            release_exe_build_options.addOption(bool, "exclude_lsp", true);
            release_exe.root_module.addOptions("build_options", release_exe_build_options);

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
