pub fn esbuild(b: *std.Build, options: EsbuildPluginOptions) ZxInitOptions.PluginOptions {
    const bin = options.bin orelse b.path("node_modules/.bin/esbuild");
    const input = options.input orelse b.path("app/main.ts");
    const output = options.output orelse b.path("{outdir}/assets/main.js");

    const cmd: *std.Build.Step.Run = .create(b, "esbuild");
    cmd.addFileArg(bin);
    cmd.addFileArg(input);

    if (options.bundle) {
        cmd.addArg("--bundle");
    }

    cmd.addPrefixedFileArg("--outfile=", output);

    if (options.log_level) |log_level| {
        cmd.addArg(b.fmt("--log-level={s}", .{@tagName(log_level)}));
    }

    if (options.format) |format| {
        cmd.addArg(b.fmt("--format={s}", .{@tagName(format)}));
    }

    if (options.platform) |platform| {
        cmd.addArg(b.fmt("--platform={s}", .{@tagName(platform)}));
    }

    if (options.target) |target| {
        cmd.addArg(b.fmt("--target={s}", .{target}));
    }

    if (options.splitting) {
        cmd.addArg("--splitting");
    }

    for (options.external) |ext| {
        cmd.addArg(b.fmt("--external:{s}", .{ext}));
    }

    // Handle minify/sourcemap based on build mode or explicit options
    const is_debug = options.optimize == .Debug;
    const is_release = !is_debug;

    if (options.minify orelse is_release) {
        cmd.addArg("--minify");
    }

    if (options.sourcemap) |sm|
        switch (sm) {
            .@"inline" => cmd.addArg("--sourcemap=inline"),
            .external => cmd.addArg("--sourcemap=external"),
            .linked => cmd.addArg("--sourcemap=linked"),
            .both => cmd.addArg("--sourcemap=both"),
        }
    else if (is_debug)
        cmd.addArg("--sourcemap=inline");

    // Add define based on build mode
    if (is_release) {
        cmd.addArgs(&.{
            "--define:__DEV__=false",
            "--define:process.env.NODE_ENV=\"production\"",
        });
    } else {
        cmd.addArgs(&.{
            "--define:__DEV__=true",
            "--define:process.env.NODE_ENV=\"development\"",
        });
    }

    // Add custom defines
    for (options.define) |def| {
        cmd.addArg(b.fmt("--define:{s}={s}", .{ def.key, def.value }));
    }

    const steps = b.allocator.alloc(ZxInitOptions.PluginOptions.PluginStep, 1) catch @panic("OOM");
    steps[0] = .{
        .command = .{
            .type = .after_transpile,
            .run = cmd,
        },
    };

    return .{
        .name = "esbuild",
        .steps = steps,
    };
}

const std = @import("std");
const builtin = @import("builtin");
const LazyPath = std.Build.LazyPath;

const EsbuildPluginOptions = struct {
    /// Path to the esbuild binary [default: `node_modules/.bin/esbuild`]
    bin: ?LazyPath = null,
    /// Input entry point file [default: `app/main.ts`]
    input: ?LazyPath = null,
    /// Output file [default: `{outdir}/assets/main.js`]
    /// `{outdir}/assets` means you can link the script like:
    /// ```html
    /// <script src="/assets/main.js"></script>
    /// ```
    output: ?LazyPath = null,
    /// Bundle all dependencies into the output files [default: `true`]
    bundle: bool = true,
    /// Minify the output (sets all --minify-* flags) [default: `true` in release, `false` in debug]
    minify: ?bool = null,
    /// Emit a source map [default: `inline` in debug, `none` in release]
    sourcemap: ?enum { @"inline", external, linked, both } = null,
    /// Disable logging [default: `silent`]
    log_level: ?enum { verbose, debug, info, warning, @"error", silent } = .@"error",
    /// Output format [default: inferred by esbuild]
    format: ?enum { iife, cjs, esm } = null,
    /// Platform target [default: `browser`]
    platform: ?enum { browser, node, neutral } = null,
    /// Environment target (e.g. es2017, chrome58, node10) [default: `esnext`]
    target: ?[]const u8 = null,
    /// Enable code splitting (currently only for esm)
    splitting: bool = false,
    /// Exclude modules from the bundle (can use * wildcards)
    external: []const []const u8 = &.{},
    /// Substitute K with V while parsing (in addition to __DEV__ and process.env.NODE_ENV)
    define: []const struct { key: []const u8, value: []const u8 } = &.{},

    // watch: bool = false, // Available with esbuild, but zig watch already handles rebuilding

    optimize: ?std.builtin.OptimizeMode = null,
};

const ZxInitOptions = @import("../init/ZxInitOptions.zig");
