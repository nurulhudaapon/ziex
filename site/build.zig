const std = @import("std");
const ziex = @import("ziex");

const build_zon = @import("build.zig.zon");

pub fn build(b: *std.Build) !void {
    // --- Target and Optimize from `zig build` arguments ---
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- Deps --- //
    const ziex_dep = b.dependency("ziex", .{});
    const playground_dep = b.dependency("playground", .{});
    const ziex_js_dep = ziex_dep.builder.dependency("ziex_js", .{});

    // --- Assets -- //
    const pg_assets = playground_dep.namedWriteFiles("playground_assets");
    const install_pg = b.addInstallDirectory(.{
        .source_dir = pg_assets.getDirectory(),
        .install_dir = .prefix,
        .install_subdir = "static/assets/playground",
    });
    b.installDirectory(.{
        .source_dir = ziex_js_dep.path("."),
        .install_dir = .prefix,
        .install_subdir = "pkg/ziex",
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
    var zx_build = try ziex.init(b, app_exe, .{
        .app = .{
            .path = b.path("app"),
            .copy_embedded_sources = true,
        },
        .client = .{
            .jsglue_href = "/assets/main.js?=" ++ build_zon.version,
        },
        .cli = .{
            .optimize = optimize,
        },
    });

    var assetsdir = zx_build.assetsdir;
    zx_build.plugin(
        ziex.plugins.tailwind(b, .{
            .input = b.path("app/assets/docs.css"),
            .output = assetsdir.path(b, "docs.css"),
            .minify = true,
            .optimize = true,
            .map = false,
        }),
    );
    zx_build.plugin(ziex.plugins.esbuild(b, .{
        .input = b.path("app/scripts/react.ts"),
        .output = assetsdir.path(b, "react.js"),
        .optimize = optimize,
    }));
    zx_build.plugin(ziex.plugins.esbuild(b, .{
        .input = b.path("app/scripts/client.ts"),
        .output = assetsdir.path(b, "main.js"),
        .optimize = optimize,
    }));
    zx_build.plugin(ziex.plugins.esbuild(b, .{
        .input = b.path("app/scripts/docs.ts"),
        .output = assetsdir.path(b, "docs.js"),
        .optimize = optimize,
    }));
    zx_build.plugin(ziex.plugins.Bun.init(.{ .build = b, .options = .{
        .inputs = &.{
            b.path("app/pages/playground/scripts/editor.ts"),
            b.path("app/pages/playground/scripts/workers/runner.ts"),
            b.path("app/pages/playground/scripts/workers/zig.ts"),
            b.path("app/pages/playground/scripts/workers/zx.ts"),
            b.path("app/pages/playground/scripts/workers/zls.ts"),
        },
        .outdir = assetsdir.path(b, "playground/"),
    } }));

    if (target.result.os.tag == .wasi)
        zx_build.addElement(.{
            .parent = .body,
            .position = .ending,
            .element = .{
                .tag = "script",
                .attributes = "src=\"/assets/main.js?=" ++ build_zon.version ++ "\"",
            },
        });
}
