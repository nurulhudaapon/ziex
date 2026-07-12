const std = @import("std");
const initlib = @import("src/build/init.zig");
const build_zon = @import("build.zig.zon");

/// Options for initializing
pub const InitOptions = initlib.InitOptions;

/// Transpiled ZX module
pub const TranslatedZx = @import("src/build/TranslatedZx.zig");

/// Initialize a Ziex project (sets up Ziex, dependencies, executables, wasm executable and `serve` step)
pub const init = initlib.init;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const enable_lsp = b.option(bool, "lsp", "Enabled zx lsp") orelse false;
    const enable_sqlite = b.option(bool, "feature-sqlite", "Enabled sqlite support") orelse false;
    const enable_postgres = b.option(bool, "feature-postgres", "Enabled postgres support") orelse false;
    const exclude_core_lang = b.option(bool, "exclude-core-lang", "Exclude core language tools (Ast/Parse/sourcemap) - only needed by CLI") orelse false;
    const version = b.option([]const u8, "version", "Version to embed in the binary") orelse build_zon.version;
    const log_level = b.option(std.log.Level, "cli-log-level", "Log level for the CLI") orelse .info;
    const zig_exe_path = b.option([]const u8, "zig-path", "Path to the zig executable") orelse "zig";

    const is_client = b.option(bool, "is-client", "Building for the browser (client)") orelse false;

    // Options
    const options = b.addOptions();
    options.addOption([]const u8, "version", version);
    options.addOption([]const u8, "description", build_zon.description);
    options.addOption([]const u8, "repository", build_zon.repository);
    options.addOption([]const u8, "homepage", build_zon.homepage);
    options.addOption([]const u8, "minimum_zig_version", build_zon.minimum_zig_version);

    const cli_options_dev = b.addOptions();
    cli_options_dev.addOption([]const u8, "zig_exe", zig_exe_path);

    // Dependencies
    const httpz_dep = b.dependency("httpz", .{ .target = target, .optimize = optimize });
    const tree_sitter_dep = b.dependency("tree_sitter", .{ .target = target, .optimize = optimize });
    const tree_sitter_zx_dep = b.dependency("tree_sitter_zx", .{ .target = target, .optimize = optimize, .@"build-shared" = false });
    const tree_sitter_mdzx_dep = b.dependency("tree_sitter_mdzx", .{ .target = target, .optimize = optimize, .@"build-shared" = false });

    // --- Features Module --- //
    const zx_core_lang_mod = b.addModule("zx_core_lang", .{ .root_source_file = b.path("src/core/root.zig"), .target = target, .optimize = optimize });
    zx_core_lang_mod.addImport("tree_sitter", tree_sitter_dep.module("tree_sitter"));
    zx_core_lang_mod.addImport("tree_sitter_zx", tree_sitter_zx_dep.module("tree_sitter_zx"));
    zx_core_lang_mod.addImport("tree_sitter_mdzx", tree_sitter_mdzx_dep.module("tree_sitter_mdzx"));

    // --- Main ZX Module --- //
    const mod = b.addModule("zx", .{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize });

    // Module feature flags (controls what gets compiled)
    const zx_module_options = b.addOptions();
    zx_module_options.addOption(bool, "exclude_core_lang", exclude_core_lang);
    zx_module_options.addOption(bool, "is_client", is_client);

    // Imports (zx)
    {
        if (!is_client) {
            if (enable_sqlite) {
                const db_sqlite_dep = b.lazyDependency("db_sqlite", .{ .target = target, .optimize = optimize });
                if (db_sqlite_dep) |a| mod.addImport("zqlite", a.module("zqlite"));
            }
            if (enable_postgres) {
                const db_postgres_dp = b.lazyDependency("db_postgres", .{ .target = target, .optimize = optimize });
                if (db_postgres_dp) |a| mod.addImport("db_postgres", a.module("postgres"));
            }

            mod.addImport("httpz", httpz_dep.module("httpz"));
        }

        if (is_client) {
            const jsz_dep = b.dependency("zig_js", .{ .target = target, .optimize = optimize });
            mod.addImport("js", jsz_dep.module("zig-js"));
        }

        if (!exclude_core_lang) mod.addImport("zx_core_lang", zx_core_lang_mod);
        mod.addOptions("zx_info", options);
        mod.addOptions("zx_module_options", zx_module_options);
    }

    // --- ZX CLI (Transpiler, Exporter, Dev Server) --- //
    const zli_dep = b.dependency("zli", .{ .target = target, .optimize = optimize });
    const exe_rootmod_opts: std.Build.Module.CreateOptions = .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "cli_options", .module = cli_options_dev.createModule() },
            .{ .name = "core_lang", .module = zx_core_lang_mod },
            .{ .name = "zx_info", .module = options.createModule() },
            .{ .name = "zli", .module = zli_dep.module("zli") },
            .{ .name = "tree_sitter", .module = tree_sitter_dep.module("tree_sitter") },
            .{ .name = "tree_sitter_zx", .module = tree_sitter_zx_dep.module("tree_sitter_zx") },
        },
    };

    const exe_build_options = b.addOptions();
    exe_build_options.addOption(bool, "enable_lsp", enable_lsp);
    exe_build_options.addOption(u2, "log_level", @intFromEnum(log_level));

    const exe = b.addExecutable(.{ .name = "zx", .root_module = b.createModule(exe_rootmod_opts) });
    exe.root_module.addOptions("build_options", exe_build_options);
    exe.root_module.addAnonymousImport("app_template", .{ .root_source_file = b.path("templates/Template.zig") });
    if (enable_lsp) {
        // const zls_dep = b.lazyDependency("zls", .{ .target = target, .optimize = optimize });
        // if (zls_dep) |zls| exe.root_module.addImport("zls", zls.module("zls"));
    }
    b.installArtifact(exe);

    // --- Steps: Run --- //
    {
        const run_step = b.step("run", "Run the app");
        const run_cmd = b.addRunArtifact(exe);
        run_step.dependOn(&run_cmd.step);
        run_cmd.step.dependOn(b.getInstallStep());
        run_cmd.addPassthruArgs();
    }

    // --- Steps: Test --- //
    {
        const mode_test = b.createModule(.{ .root_source_file = b.path("src/root.zig") });
        if (b.lazyDependency("db_sqlite", .{})) |ad| mode_test.addImport("zqlite", ad.module("zqlite"));
        mode_test.addOptions("zx_info", options);
        mode_test.addOptions("zx_module_options", zx_module_options);
        mode_test.addImport("zx_core_lang", zx_core_lang_mod);

        const testing_mod = b.createModule(.{
            .root_source_file = b.path("test/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "cli_options", .module = cli_options_dev.createModule() },
                .{ .name = "zx", .module = mode_test },
                .{ .name = "html_hover", .module = b.createModule(.{
                    .root_source_file = b.path("src/lsp/html_hover.zig"),
                    .imports = &.{
                        .{ .name = "core_lang", .module = zx_core_lang_mod },
                    },
                }) },
                .{ .name = "builder", .module = b.createModule(.{
                    .root_source_file = b.path("src/cli/dev/Builder.zig"),
                }) },
            },
        });
        const testing_mod_tests = b.addTest(.{
            .root_module = testing_mod,
            .test_runner = .{ .path = b.path("test/runner.zig"), .mode = .simple },
        });
        const test_run = b.addRunArtifact(testing_mod_tests);
        test_run.step.dependOn(b.getInstallStep());

        const test_step = b.step("test", "Run tests");
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

    // --- Steps: Dev (Runs e2e step for site/) --- //
    {
        const e2e_step = b.step("e2e", "Run the site in development mode");
        const e2e_cmd = b.addSystemCommand(&.{ "npx", "playwright", "test" });
        e2e_cmd.setCwd(b.path("test/e2e"));
        e2e_step.dependOn(&e2e_cmd.step);
        e2e_cmd.addPassthruArgs();
    }

    // --- Steps: Dev (Runs dev step for site/) --- //
    {
        const dev_step = b.step("dev", "Run the site in development mode");
        const dev_cmd = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "dev" });
        dev_cmd.setCwd(b.path("site"));
        dev_step.dependOn(&dev_cmd.step);
        dev_cmd.addPassthruArgs();
    }

    // --- Steps: Site (Runs build step for site/) --- //
    {
        const site_step = b.step("site", "Build the site");
        const site_cmd = b.addSystemCommand(&.{ b.graph.zig_exe, "build" });
        site_cmd.setCwd(b.path("site"));
        site_step.dependOn(&site_cmd.step);
        site_cmd.addPassthruArgs();
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

        if (b.root.root_dir.handle.access(b.graph.io, "vendor/webref", .{})) |_| {} else |_| {
            const sync_cmd = b.addSystemCommand(&.{ "./tools/syncvendor", "webref" });
            css_gen_run.step.dependOn(&sync_cmd.step);
        }

        css_gen_step.dependOn(&css_gen_run.step);
    }

    // --- Steps: Events Generator --- //
    {
        const events_gen_step = b.step("eventsgen", "Generate DOM event types from webref");

        const events_gen_exe = b.addExecutable(.{
            .name = "eventsgen",
            .root_module = b.createModule(.{
                .root_source_file = b.path("tools/codegen/events.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        const events_gen_run = b.addRunArtifact(events_gen_exe);

        if (b.root.root_dir.handle.access(b.graph.io, "vendor/webref", .{})) |_| {} else |_| {
            const sync_cmd = b.addSystemCommand(&.{ "./tools/syncvendor", "webref" });
            events_gen_run.step.dependOn(&sync_cmd.step);
        }

        events_gen_step.dependOn(&events_gen_run.step);
    }

    // --- Steps: HTML Docs Generator --- //
    {
        const html_docs_gen_step = b.step("htmldocsgen", "Generate HTML element/attribute docs from webref");

        const html_docs_gen_exe = b.addExecutable(.{
            .name = "htmldocsgen",
            .root_module = b.createModule(.{
                .root_source_file = b.path("tools/codegen/html_docs.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        const html_docs_gen_run = b.addRunArtifact(html_docs_gen_exe);

        if (b.root.root_dir.handle.access(b.graph.io, "vendor/webref", .{})) |_| {} else |_| {
            const sync_cmd = b.addSystemCommand(&.{ "./tools/syncvendor", "webref" });
            html_docs_gen_run.step.dependOn(&sync_cmd.step);
        }

        html_docs_gen_step.dependOn(&html_docs_gen_run.step);
    }

    // --- Steps: Sync Benchmark --- //
    {
        const syncbench_step = b.step("syncbench", "Run synchronization benchmark from GH actions");

        const syncbench_exe = b.addExecutable(.{
            .name = "syncbench",
            .root_module = b.createModule(.{
                .root_source_file = b.path("site/app/pages/bench.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        const syncbench_run = b.addRunArtifact(syncbench_exe);
        syncbench_step.dependOn(&syncbench_run.step);
        syncbench_run.addPassthruArgs();
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

            // Sub-modules for release
            const release_core_lang_mod = b.createModule(.{ .root_source_file = b.path("src/core/root.zig"), .target = resolved_target, .optimize = .ReleaseSafe });
            release_core_lang_mod.addImport("tree_sitter", release_tree_sitter_dep.module("tree_sitter"));
            release_core_lang_mod.addImport("tree_sitter_zx", release_tree_sitter_zx_dep.module("tree_sitter_zx"));
            release_core_lang_mod.addImport("tree_sitter_mdzx", release_tree_sitter_mdzx_dep.module("tree_sitter_mdzx"));

            const release_exe = b.addExecutable(.{
                .name = "zx",
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/main.zig"),
                    .target = resolved_target,
                    .optimize = .ReleaseSafe,
                    .imports = &.{
                        .{ .name = "cli_options", .module = cli_options_rel.createModule() },
                        .{ .name = "core_lang", .module = release_core_lang_mod },
                        .{ .name = "zx_info", .module = options.createModule() },
                        .{ .name = "zli", .module = zli_dep.module("zli") },
                        .{ .name = "tree_sitter", .module = release_tree_sitter_dep.module("tree_sitter") },
                        .{ .name = "tree_sitter_zx", .module = release_tree_sitter_zx_dep.module("tree_sitter_zx") },
                    },
                }),
            });
            const release_enable_lsp = false; // TODO: enable lsp when zls is updated to latest zig 0.17
            const release_exe_build_options = b.addOptions();
            release_exe_build_options.addOption(bool, "enable_lsp", release_enable_lsp);
            release_exe_build_options.addOption(u2, "log_level", @intFromEnum(log_level));

            release_exe.root_module.addOptions("build_options", release_exe_build_options);
            release_exe.root_module.addAnonymousImport("app_template", .{ .root_source_file = b.path("templates/Template.zig") });

            if (release_enable_lsp) {
                // const zls_dep = b.lazyDependency("zls", .{ .target = target, .optimize = .ReleaseSafe });
                // if (zls_dep) |zls| release_exe.root_module.addImport("zls", zls.module("zls"));
            }

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

/// Transpile a single `.zx` / `.mdzx` file into a `TranslatedZx`, mirroring
/// `std.Build.addTranslateC` (one root source → one cached translate step →
/// `createModule()` / `addModule()`).
///
///     const tzx = ziex.addTranslateZx(b, .{ .root_source_file = b.path("icons.zx") });
///     const icons = tzx.createModule();
///     icons.addImport("zx", zx.module);   // `zx` from `ziex.init`
///
/// Prefer this over directory transpile when you want per-file rebuilds under
/// `zig build --watch`. The host transpiler CLI is resolved for the host
/// target so it can execute during the build; it never enters the runtime
/// module graph.
pub fn addTranslateZx(b: *std.Build, opts: TranslatedZx.Options) *TranslatedZx {
    const zx_host_dep = b.dependencyFromBuildZig(@This(), .{});
    return TranslatedZx.create(b, zx_host_dep.artifact("zx"), opts);
}

pub const info = .{
    .version = build_zon.version,
    .description = build_zon.description,
    .repository = build_zon.repository,
    .homepage = build_zon.homepage,
    .minimum_zig_version = build_zon.minimum_zig_version,
};
