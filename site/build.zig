const std = @import("std");
const ziex = @import("ziex");

const build_zon = @import("build.zig.zon");

pub fn build(b: *std.Build) !void {
    // --- Target and Optimize from `zig build` arguments ---
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- Deps --- //
    const ziex_dep = b.dependency("ziex", .{ .optimize = optimize, .target = target });
    const tree_sitter_dep = ziex_dep.builder.dependency("tree_sitter", .{ .optimize = optimize, .target = target });
    const tree_sitter_zx_dep = ziex_dep.builder.dependency("tree_sitter_zx", .{ .optimize = optimize, .target = target, .@"build-shared" = false });
    // const tree_sitter_mdzx_dep = ziex_dep.builder.dependency("tree_sitter_mdzx", .{ .optimize = optimize, .target = target, .@"build-shared" = false });

    // --- Playground Assets --- //
    const wasm_target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .wasi });
    const wasm_optimize: std.builtin.OptimizeMode = .ReleaseSmall;

    const playground_dep = b.dependency("playground", .{});
    const zls_dep = playground_dep.builder.dependency("zls", .{ .target = wasm_target, .optimize = wasm_optimize });
    const zx_wasm_dep = b.dependency("ziex", .{ .target = wasm_target, .optimize = wasm_optimize });
    const zig_dep = playground_dep.builder.dependency("zig", .{
        .target = wasm_target,
        .optimize = wasm_optimize,
        .@"version-string" = @as([]const u8, "0.15.1"),
        .@"no-lib" = true,
        .dev = "wasm",
    });

    const zx_exe = zx_wasm_dep.artifact("zx");
    const zls_exe = b.addExecutable(.{
        .name = "zls",
        .root_module = b.createModule(.{
            .root_source_file = playground_dep.path("src/zls.zig"),
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

    // -- zx.tar.gz (only include files needed for playground compilation)
    const run_zx_tar = b.addSystemCommand(&.{ "tar", "-czf" });
    run_zx_tar.has_side_effects = true;
    const zx_tar_gz = run_zx_tar.addOutputFileArg("zx.tar.gz");
    run_zx_tar.addArgs(&.{
        "--exclude", "src/cli",
        "--exclude", "src/lsp",
        "--exclude", "src/tui",
        "--exclude", "src/build",
        "--exclude", "src/main.zig",
    });
    run_zx_tar.addArg("-C");
    run_zx_tar.addDirectoryArg(zx_wasm_dep.path("."));
    run_zx_tar.addArg("src");

    const playground_assets = b.addNamedWriteFiles("playground_assets");
    _ = playground_assets.addCopyFile(zls_exe.getEmittedBin(), "zls.wasm");
    _ = playground_assets.addCopyFile(zig_exe.getEmittedBin(), b.fmt("zig-{s}.wasm", .{ziex.info.minimum_zig_version}));
    _ = playground_assets.addCopyFile(zx_exe.getEmittedBin(), b.fmt("zx-{s}.wasm", .{ziex.info.version}));
    _ = playground_assets.addCopyFile(zig_tar_gz, b.fmt("zig-{s}.tar.gz", .{ziex.info.minimum_zig_version}));
    _ = playground_assets.addCopyFile(zx_tar_gz, b.fmt("zx-{s}.tar.gz", .{ziex.info.version}));

    const install_pg = b.addInstallDirectory(.{
        .source_dir = playground_assets.getDirectory(),
        .install_dir = .prefix,
        .install_subdir = "static/assets/playground",
    });

    // -- Steps: pg - installs playground assets --- //
    const pg_step = b.step("pg", "Install playground assets");
    pg_step.dependOn(&install_pg.step);

    // --- ZX App Executable --- //
    const app_exe = b.addExecutable(.{
        .name = "ziex_dev",
        .root_module = b.createModule(.{
            .root_source_file = b.path("app/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    app_exe.root_module.addImport("tree_sitter", tree_sitter_dep.module("tree_sitter"));
    app_exe.root_module.addImport("tree_sitter_zx", tree_sitter_zx_dep.module("tree_sitter_zx"));
    app_exe.step.dependOn(&install_pg.step);

    // --- ZX setup: wires dependencies and adds `zx`/`dev` build steps --- //
    var ziex_b = try ziex.init(b, app_exe, .{
        .app = .{
            // .path = b.path("app"),
            // .base_path = "/test",
            .copy_embedded_sources = true,
        },
        .client = .{ .jsglue_href = "/assets/_/main.js" },
        .cli = .{ .optimize = optimize },
    });

    var assetsdir = ziex_b.assetsdir;
    const tailwindcss_b = tailwindcss.addBuild(b, .{
        .config = .{
            .input = b.path("app/styles/tailwind.css"),
            // .minify = true,
            // .optimize = true,
            // .map = false,
        },
    });
    const css_install = b.addInstallFile(tailwindcss_b.file, "static/assets/_/tailwind.css");
    b.default_step.dependOn(&css_install.step);

    // ziex_b.plugin(ziex.plugins.esbuild(b, .{
    //     .input = b.path("app/scripts/react.ts"),
    //     .output = assetsdir.path(b, "react.js"),
    //     .optimize = optimize,
    // }));
    ziex_b.plugin(ziex.plugins.esbuild(b, .{
        .input = b.path("app/scripts/client.ts"),
        .output = assetsdir.path(b, "_/main.js"),
        .optimize = optimize,
    }));
    ziex_b.plugin(ziex.plugins.esbuild(b, .{
        .input = b.path("app/scripts/docs.ts"),
        .output = assetsdir.path(b, "docs.js"),
        .optimize = optimize,
    }));

    // TODO: Fix issue with outfile
    // bunjs.addBuildRun(b, .{ .config = .{
    //     .entrypoints = &.{b.path("app/scripts/docs.ts")},
    //     .outfile = assetsdir.path(b, "docs.js"),
    // } });
    const bi = bunjs.addBuild(b, .{
        .name = "playground_scripts",
        .config = .{
            .entrypoints = &.{
                b.path("app/pages/playground/scripts/editor.ts"),
                b.path("app/pages/playground/scripts/workers/runner.ts"),
                b.path("app/pages/playground/scripts/workers/zig.ts"),
                b.path("app/pages/playground/scripts/workers/zx.ts"),
                b.path("app/pages/playground/scripts/workers/zls.ts"),
            },
            .define = &.{
                .{
                    .key = "VERSION",
                    .value = b.fmt("\"{s}\"", .{ziex.info.version}),
                },
                .{
                    .key = "ZIG_VERSION",
                    .value = b.fmt("\"{s}\"", .{ziex.info.minimum_zig_version}),
                },
            },
            // .outdir = assetsdir.path(b, "playground/"),
        },
    });

    b.installDirectory(.{
        .source_dir = bi.dir,
        .install_dir = .prefix,
        .install_subdir = "static/assets/playground",
    });

    b.installDirectory(.{
        .source_dir = ziex_b.ziex_js.dep.path("."),
        .install_dir = .prefix,
        .include_extensions = &.{ ".js", ".ts" },
        .install_subdir = "pkg/ziex",
    });

    // ziex_b.installZiexJs(.{});
}

const bunjs = @import("bunjs");
const tailwindcss = @import("tailwindcss");
