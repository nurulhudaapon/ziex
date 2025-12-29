// Tailwind Plugin Example (lines 1-29)
const zx = @import("zx");
const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    const zx_dep = b.dependency("zx", .{ .target = target, .optimize = optimize });
    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("site/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    try zx.init(b, exe, .{
        .plugins = &.{
            zx.plugins.tailwind(b, .{
                .bin = b.path("node_modules/.bin/tailwindcss"),
                .input = b.path("site/assets/styles.css"),
                .output = b.path("{outdir}/assets/styles.css"),
                .minify = optimize != .Debug,
            }),
        },
    });
}

// Esbuild Plugin Example (lines 31-56)
const zx = @import("zx");
const std = @import("std");

pub fn build(b: *std.Build) !void {
    // ... setup code ...

    try zx.init(b, exe, .{
        .plugins = &.{
            zx.plugins.esbuild(b, .{
                .bin = b.path("node_modules/.bin/esbuild"),
                .input = b.path("site/main.ts"),
                .output = b.path("{outdir}/assets/main.js"),
                .bundle = true,
                .format = .esm,
                .platform = .browser,
                .target = "es2020",
                .external = &.{ "react", "react-dom" },
                .define = &.{
                    .{ .key = "API_URL", .value = "\"https://api.example.com\"" },
                },
            }),
        },
    });
}

// Combined Plugins Example (lines 58-70)
try zx.init(b, exe, .{
    .plugins = &.{
        zx.plugins.esbuild(b, .{
            .input = b.path("site/main.ts"),
            .output = b.path("{outdir}/assets/main.js"),
        }),
        zx.plugins.tailwind(b, .{
            .input = b.path("site/assets/styles.css"),
            .output = b.path("{outdir}/assets/styles.css"),
        }),
    },
});

// Custom Plugin Example (lines 72-107)
const zx = @import("zx");
const std = @import("std");

pub fn build(b: *std.Build) !void {
    // ... setup code ...

    try zx.init(b, exe, .{
        .plugins = &.{
            // Custom plugin using PluginOptions directly
            createImageOptimizer(b),
        },
    });
}

fn createImageOptimizer(b: *std.Build) zx.ZxInitOptions.PluginOptions {
    const cmd = std.Build.Step.Run.create(b, "optimize-images");
    
    // Add your custom command
    cmd.addArgs(&.{ "npx", "imagemin", "site/public/**/*", "--out-dir={outdir}/public" });
    
    // Allocate steps array
    const steps = b.allocator.alloc(zx.ZxInitOptions.PluginOptions.PluginStep, 1) catch @panic("OOM");
    steps[0] = .{
        .command = .{
            .type = .after_transpile,  // Run after ZX transpilation
            .run = cmd,
        },
    };
    
    return .{
        .name = "image-optimizer",
        .steps = steps,
    };
}

