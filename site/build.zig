const std = @import("std");
const zx = @import("zx");
const build_zon = @import("build.zig.zon");

pub fn build(b: *std.Build) !void {
    // --- Target and Optimize from `zig build` arguments ---
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- ZX App Executable ---
    const app_exe = b.addExecutable(.{
        .name = "ziex_dev",
        .root_module = b.createModule(.{
            .root_source_file = b.path("app/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // --- ZX setup: wires dependencies and adds `zx`/`dev` build steps ---
    var zx_build = try zx.init(b, app_exe, .{
        .app = .{
            .path = b.path("app"),
            .copy_embedded_sources = true,
        },
        .client = .{
            .jsglue_href = "/assets/main.js?=" ++ build_zon.version,
        },
    });

    var assetsdir = zx_build.assetsdir;
    zx_build.addPlugin(
        zx.plugins.tailwind(b, .{
            .input = b.path("app/assets/docs.css"),
            .output = assetsdir.path(b, "docs.css"),
            .minify = true,
            .optimize = true,
            .map = false,
        }),
    );
    zx_build.addPlugin(zx.plugins.esbuild(b, .{
        .input = b.path("app/scripts/react.ts"),
        .output = assetsdir.path(b, "react.js"),
        .optimize = optimize,
    }));
    zx_build.addPlugin(zx.plugins.esbuild(b, .{
        .input = b.path("app/main.ts"),
        .output = assetsdir.path(b, "main.js"),
        .optimize = optimize,
    }));
    zx_build.addPlugin(zx.plugins.esbuild(b, .{
        .input = b.path("app/scripts/docs.ts"),
        .output = assetsdir.path(b, "docs.js"),
        .optimize = optimize,
    }));

    zx_build.addPlugin(zx.plugins.Bun.init(.{
        .build = b,
        .options = .{
            .inputs = &.{
                b.path("app/pages/playground/scripts/editor.ts"),
                b.path("app/pages/playground/scripts/workers/runner.ts"),
                b.path("app/pages/playground/scripts/workers/zig.ts"),
                b.path("app/pages/playground/scripts/workers/zx.ts"),
                b.path("app/pages/playground/scripts/workers/zls.ts"),
            },
            .outdir = assetsdir.path(b, "playground/"),
        },
    }));
}
