const std = @import("std");
const ziex = @import("ziex");

const build_zon = @import("build.zig.zon");

pub fn build(b: *std.Build) !void {
    // --- Target and Optimize from `zig build` arguments ---
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- Deps --- //
    const playground_dep = b.dependency("playground", .{});

    // --- Assets -- //
    const pg_assets = playground_dep.namedWriteFiles("playground_assets");
    const install_pg = b.addInstallDirectory(.{
        .source_dir = pg_assets.getDirectory(),
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
    app_exe.step.dependOn(&install_pg.step);

    // --- ZX setup: wires dependencies and adds `zx`/`dev` build steps --- //
    var ziex_b = try ziex.init(b, app_exe, .{
        .app = .{
            .path = b.path("app"),
            .copy_embedded_sources = true,
        },
        .client = .{ .jsglue_href = "/assets/_/main.js?=" ++ build_zon.version },
        .cli = .{ .optimize = optimize },
    });

    var assetsdir = ziex_b.assetsdir;
    const tailwindcss_b = tailwindcss.addBuild(b, .{
        .config = .{
            .input = b.path("app/assets/docs.css"),
            // .output = assetsdir.path(b, "docs.css"),
            .minify = true,
            .optimize = true,
            .map = false,
        },
    });
    _ = b.addInstallFile(tailwindcss_b.file, "static/assets/docs.css");

    ziex_b.plugin(ziex.plugins.esbuild(b, .{
        .input = b.path("app/scripts/react.ts"),
        .output = assetsdir.path(b, "react.js"),
        .optimize = optimize,
    }));
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
        .name = "pg-assets",
        .config = .{
            .entrypoints = &.{
                b.path("app/pages/playground/scripts/editor.ts"),
                b.path("app/pages/playground/scripts/workers/runner.ts"),
                b.path("app/pages/playground/scripts/workers/zig.ts"),
                b.path("app/pages/playground/scripts/workers/zx.ts"),
                b.path("app/pages/playground/scripts/workers/zls.ts"),
            },
            // .outdir = assetsdir.path(b, "playground/"),
        },
    });

    b.installDirectory(.{
        .source_dir = bi.dir,
        .install_dir = .prefix,
        .install_subdir = "static/test/playground",
    });
}

const bunjs = @import("bunjs");
const tailwindcss = @import("tailwindcss");
