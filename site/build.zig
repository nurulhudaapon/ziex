const std = @import("std");
const ziex = @import("ziex");

const build_zon = @import("build.zig.zon");

pub fn build(b: *std.Build) !void {
    // --- Target and Optimize from `zig build` arguments ---
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const id = assetId(b, optimize);
    const log_level = b.option(std.log.Level, "log-level", "Log level: debug, info, warn, error") orelse .info;
    const build_zig = b.option(bool, "build-zig", "Build zig/zls/compiler_rt wasm from source") orelse false;

    const jsbinding_name = b.fmt("app{s}.js", .{id});

    const app_features: ziex.InitOptions.AppOptions.FeatureOptions = .{
        .sqlite = .enabled,
        // .postgres = .enabled,
        .kv = .enabled,
        .cache = .enabled,
    };

    // --- Deps --- //
    const ziex_dep = b.dependency("ziex", .{ .optimize = optimize, .target = target });
    const tree_sitter_dep = ziex_dep.builder.dependency("tree_sitter", .{ .optimize = optimize, .target = target });
    const tree_sitter_zx_dep = ziex_dep.builder.dependency("tree_sitter_zx", .{ .optimize = optimize, .target = target, .@"build-shared" = false });
    // const tree_sitter_mdzx_dep = ziex_dep.builder.dependency("tree_sitter_mdzx", .{ .optimize = optimize, .target = target, .@"build-shared" = false });
    const ziex_jsbindings_dep = b.dependency("ziex_jsbindings", .{
        .optimize = optimize,
        .target = target,
        .@"type-decl" = false,
        .@"feature-kv-client" = if (app_features.kv) |k| k.client != null else false,
        .@"feature-kv-server" = if (app_features.kv) |k| k.server != null else false,
        .@"feature-sqlite" = if (app_features.sqlite) |s| s.server != null else false,
    });

    const pg_step = b.step("pg", "Install playground assets");
    const zls_version = "0.16.0";
    const playground_zig_version = "0.17.0-dev.1158+1d1193aa7";

    // --- Playground Assets --- //
    {
        const wasm_target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .wasi });
        const wasm_optimize: std.builtin.OptimizeMode = .ReleaseSmall;

        const zx_wasm_dep = b.dependency("ziex", .{ .target = wasm_target, .optimize = wasm_optimize });
        const zx_exe = zx_wasm_dep.artifact("zx");

        // -- zx.tar.gz (only include files needed for playground compilation)
        const run_zx_tar = b.addSystemCommand(&.{ "tar", "-czf" });
        run_zx_tar.setName("pack zx sources (playground)");
        run_zx_tar.has_side_effects = true;
        const zx_tar_gz = run_zx_tar.addOutputFileArg("zx.tar.gz");
        run_zx_tar.addArgs(&.{
            "--exclude",
            "src/cli",
            "--exclude",
            "src/cli.zig",
            "--exclude",
            "src/lsp",
            "--exclude",
            "src/tui",
            "--exclude",
            "src/main.zig",
        });
        run_zx_tar.addArg("-C");
        run_zx_tar.addDirectoryArg(zx_wasm_dep.path("."));
        run_zx_tar.addArg("src");

        const run_jsz_tar = b.addSystemCommand(&.{ "tar", "-czf" });
        run_jsz_tar.setName("pack jsz sources (playground)");
        run_jsz_tar.has_side_effects = true;
        const jsz_tar_gz = run_jsz_tar.addOutputFileArg("jsz.tar.gz");
        run_jsz_tar.addArg("-C");
        run_jsz_tar.addDirectoryArg(zx_wasm_dep.path("vendor/jsz"));
        run_jsz_tar.addArg("src");

        const ziex_js_files = ziex_jsbindings_dep.namedWriteFiles("ziex_js");
        const pg_init_js = ziex_js_files.getDirectory().path(b, "wasm/init.js");

        const playground_assets = b.addNamedWriteFiles("playground_assets");
        _ = playground_assets.addCopyFile(zx_exe.getEmittedBin(), b.fmt("zx-{s}-{s}.wasm", .{ ziex.info.version, id }));
        _ = playground_assets.addCopyFile(zx_tar_gz, b.fmt("zx-{s}-{s}.tar.gz", .{ ziex.info.version, id }));
        _ = playground_assets.addCopyFile(jsz_tar_gz, "jsz.tar.gz");
        _ = playground_assets.addCopyFile(pg_init_js, "init.js");

        if (build_zig) {
            const zls_wasm_url = "https://playground.zigtools.org/assets/zls-Cv7Q1mLZ.wasm";
            const zig_dep = b.dependency("zig", .{
                .target = wasm_target,
                .optimize = wasm_optimize,
                .@"version-string" = @as([]const u8, playground_zig_version),
                .@"no-lib" = true,
                .dev = "wasm",
            });

            const lib_compiler_rt = b.addLibrary(.{
                .linkage = .static,
                .name = "compiler_rt",
                .root_module = b.createModule(.{
                    .root_source_file = zig_dep.path("lib/compiler_rt.zig"),
                    .target = wasm_target,
                    .optimize = wasm_optimize,
                }),
            });
            const zig_exe = zig_dep.artifact("zig");

            // -- zig.tar.gz
            const run_tar = b.addSystemCommand(&.{ "tar", "-czf" });
            run_tar.setName("pack zig stdlib (playground)");
            const zig_tar_gz = run_tar.addOutputFileArg("zig.tar.gz");
            run_tar.addArg("-C");
            run_tar.addDirectoryArg(zig_dep.path("."));
            run_tar.addArg("lib/std");

            const pg_get_zls = b.addSystemCommand(&.{ "curl", "-LSsf", zls_wasm_url, "-o" });
            pg_get_zls.setName("fetch zls.wasm (playground)");
            pg_get_zls.expectExitCode(0);
            _ = playground_assets.addCopyFile(pg_get_zls.addOutputFileArg("zls.wasm"), b.fmt("zls-{s}.wasm", .{zls_version}));
            _ = playground_assets.addCopyFile(zig_exe.getEmittedBin(), b.fmt("zig-{s}.wasm", .{playground_zig_version}));
            _ = playground_assets.addCopyFile(lib_compiler_rt.getEmittedBin(), b.fmt("libcompiler_rt-{s}.a", .{playground_zig_version}));
            _ = playground_assets.addCopyFile(zig_tar_gz, b.fmt("zig-{s}.tar.gz", .{playground_zig_version}));
        } else {
            const assets_dep = try b.dependencyLazy("assets", .{});
            _ = playground_assets.addCopyFile(
                assets_dep.path(b.fmt("assets/zls-{s}.wasm", .{zls_version})),
                b.fmt("zls-{s}.wasm", .{zls_version}),
            );
            _ = playground_assets.addCopyFile(
                assets_dep.path(b.fmt("assets/zig-{s}.wasm", .{playground_zig_version})),
                b.fmt("zig-{s}.wasm", .{playground_zig_version}),
            );
            _ = playground_assets.addCopyFile(
                assets_dep.path(b.fmt("assets/libcompiler_rt-{s}.a", .{playground_zig_version})),
                b.fmt("libcompiler_rt-{s}.a", .{playground_zig_version}),
            );
            _ = playground_assets.addCopyFile(
                assets_dep.path(b.fmt("assets/zig-{s}.tar.gz", .{playground_zig_version})),
                b.fmt("zig-{s}.tar.gz", .{playground_zig_version}),
            );
        }

        const install_pg = b.addInstallDirectory(.{
            .source_dir = playground_assets.getDirectory(),
            .install_dir = .prefix,
            .install_subdir = "static/assets/playground",
        });
        install_pg.step.name = "install playground wasm assets";

        // -- Steps: pg - installs playground assets --- //
        pg_step.dependOn(&install_pg.step);
    }

    // --- ZX App Executable --- //
    const app_exe = b.addExecutable(.{
        .name = "ziex_dev",
        .root_module = b.createModule(.{
            .root_source_file = b.path("app/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    app_exe.root_module.addImport("initoptions", b.createModule(.{
        .root_source_file = b.path("../src/build/init/InitOptions.zig"),
        .target = target,
        .optimize = optimize,
    }));
    app_exe.root_module.addImport("tree_sitter", tree_sitter_dep.module("tree_sitter"));
    app_exe.root_module.addImport("tree_sitter_zx", tree_sitter_zx_dep.module("tree_sitter_zx"));
    if (!target.result.cpu.arch.isWasm())
        if (b.lazyDependency("lunasvg", .{ .optimize = optimize, .target = target })) |lunasvg|
            app_exe.root_module.addImport("lunasvg", lunasvg.module("lunasvg"));

    app_exe.step.dependOn(pg_step);

    // --- ZX setup: wires dependencies and adds `zx`/`dev` build steps --- //
    var zx = try ziex.init(b, app_exe, .{
        .app = .{
            // .path = b.path("app"),
            // .base_path = "/test",
            .features = app_features,
            .client = .{
                .bindings = .{
                    .href = b.fmt("/assets/{s}", .{jsbinding_name}),
                    .install_subdir = "pkg/ziex",
                    .build = .enabled,
                },
            },
        },
        .cli = .{ .optimize = optimize, .log_level = log_level, .zig_path = "zig" },
    });
    zx.addImport("cli_args", ziex_dep.module("cli_args"));

    // --- ZX Components --- //
    if (true) {
        // Single File
        const icons_mod = zx.addComponent(.{ .root_source_file = b.path("component/icon.zx") });
        zx.app.module.addImport("icon", icons_mod);
        // multifile
        zx.addComponentImport("component", .{ .root_source_file = b.path("component/main.zx") });
        // from deps
        const ui_dep = b.dependency("ui", .{});
        const ui_mod = ui_dep.module("ui");
        ui_mod.addImport("zx", zx.zx_module);
        zx.addImport("ui", ui_mod);

        const template_path = b.path("../templates/_base/app");
        // Layout
        const template_layout_mod = zx.addComponent(.{
            .root_source_file = template_path.path(b, "pages/layout.zx"),
        });
        zx.addImport("tmpl_layout", template_layout_mod);
        // Home page
        const template_ui_root_mod = zx.addComponent(.{
            .root_source_file = template_path.path(b, "pages/page.zx"),
        });
        zx.addImport("tmpl_home", template_ui_root_mod);

        // /form page
        const template_form_root_mod = zx.addComponent(.{
            .root_source_file = template_path.path(b, "pages/form/page.zx"),
        });
        zx.addImport("tmpl_form", template_form_root_mod);

        // /actions
        const template_actions_root_mod = zx.addComponent(.{
            .root_source_file = template_path.path(b, "pages/actions/page.zx"),
        });
        zx.addImport("tmpl_actions", template_actions_root_mod);

        // /actions/client
        const template_actions_client_mod = zx.addComponent(.{
            .root_source_file = template_path.path(b, "pages/actions/client/page.zx"),
        });
        zx.addImport("tmpl_actions_client", template_actions_client_mod);

        // /actions/server
        const template_actions_server_mod = zx.addComponent(.{
            .root_source_file = template_path.path(b, "pages/actions/server/page.zx"),
        });
        zx.addImport("tmpl_actions_server", template_actions_server_mod);
    }

    if (true) {
        const tailwindcss_b = tailwindcss.addBuild(b, .{
            .config = .{
                .input = b.path("app/styles/tailwind.css"),
                // .minify = true,
                // .optimize = true,
                // .map = false,
            },
        });
        const css_install = b.addInstallFile(tailwindcss_b.file, "static/assets/_/tailwind.css");
        css_install.step.name = "install tailwind.css";
        b.default_step.dependOn(&css_install.step);
    }

    if (true) {
        const css_builds = tailwindcss.addBuilds(b, &.{
            .{
                .name = "docs",
                .config = .{
                    .input = b.path("app/assets/docs.css"),
                    // .minify = true,
                    .optimize = true,
                    // .map = false,
                },
            },
            .{
                .name = "home",
                .config = .{
                    .input = b.path("app/assets/home.css"),
                    // .minify = true,
                    .optimize = true,
                    // .map = false,
                },
            },
        });

        for (css_builds) |css_build| {
            const css_fn = css_build.name orelse return error.MissingName;
            const css_install = b.addInstallFile(css_build.file, b.fmt("static/assets/_/{s}.css", .{css_fn}));
            css_install.step.name = b.fmt("install {s}.css", .{css_fn});
            b.default_step.dependOn(&css_install.step);
        }
    }

    if (true) {
        const is_release = optimize != .Debug;
        const site_scripts = esbuild.addBuild(b, .{
            .name = "site_scripts",
            .config = .{
                .entrypoints = &.{
                    b.path("app/scripts/client.ts"),
                    b.path("app/scripts/docs.ts"),
                    b.path("app/scripts/home.ts"),
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

        // const install_main_js = b.addInstallFile(site_scripts.dir.path(b, "client.js"), b.fmt("static/assets/main{s}.js", .{id}));
        const ziex_js_files = ziex_jsbindings_dep.namedWriteFiles("ziex_js");
        const init_name = if (is_release) "init.js" else "init.dev.js";
        const init_js = ziex_js_files.getDirectory().path(b, b.fmt("wasm/{s}", .{init_name}));
        const install_main_js = b.addInstallFile(init_js, b.fmt("static/assets/{s}", .{jsbinding_name}));
        install_main_js.step.name = "install app.js bindings";
        const install_docs_js = b.addInstallFile(site_scripts.dir.path(b, "docs.js"), "static/assets/docs.js");
        install_docs_js.step.name = "install docs.js";
        const install_home_js = b.addInstallFile(site_scripts.dir.path(b, "home.js"), "static/assets/home.js");
        install_home_js.step.name = "install home.js";
        b.default_step.dependOn(&install_main_js.step);
        b.default_step.dependOn(&install_docs_js.step);
        b.default_step.dependOn(&install_home_js.step);
    }

    if (true) {
        const playground_scripts = esbuild.addBuild(b, .{
            .name = "playground_scripts",
            .config = .{
                .entrypoints = &.{
                    b.path("app/pages/playground/scripts/editor.ts"),
                    b.path("app/pages/playground/scripts/workers/runner.ts"),
                    b.path("app/pages/playground/scripts/workers/zig.ts"),
                    b.path("app/pages/playground/scripts/workers/zx.ts"),
                    b.path("app/pages/playground/scripts/workers/zls.ts"),
                },
                .format = .esm,
                .splitting = false,
                .platform = .browser,
                .minify = optimize != .Debug,
                .define = &.{
                    .{
                        .key = "VERSION",
                        .value = b.fmt("\"{s}-{s}\"", .{ ziex.info.version, id }),
                    },
                    .{
                        .key = "ZIG_VERSION",
                        .value = b.fmt("\"{s}\"", .{playground_zig_version}),
                    },
                    .{
                        .key = "ZLS_VERSION",
                        .value = b.fmt("\"{s}\"", .{zls_version}),
                    },
                },
            },
        });

        const install_playground_scripts = b.addInstallDirectory(.{
            .source_dir = playground_scripts.dir,
            .install_dir = .prefix,
            .install_subdir = "static/assets/playground",
        });
        install_playground_scripts.step.name = "install playground scripts";
        b.default_step.dependOn(&install_playground_scripts.step);
    }

    if (true) {
        const branding_dep = b.dependency("branding", .{});
        const install_branding = b.addInstallDirectory(.{
            .source_dir = branding_dep.path("."),
            .install_dir = .prefix,
            .install_subdir = "static/assets/branding",
            .include_extensions = &.{ "webp", "svg", "png", "gif" },
        });
        install_branding.step.name = "install branding";
        b.default_step.dependOn(&install_branding.step);
    }
}

fn assetId(_: *std.Build, optimize: std.builtin.OptimizeMode) []const u8 {
    if (optimize == .Debug) return ".dev";
    return "";

    // TODO: use ziex_builder.addStaticInstallFile(.{src: lazypath, dest_name: "assets/app.{hash}.js"}) once this is implemented
}

const esbuild = @import("esbuild");
const tailwindcss = @import("tailwindcss");
