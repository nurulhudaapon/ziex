pub fn tailwind(b: *std.Build, options: TailwindPluginOptions) ZxInitOptions.PluginOptions {
    const bin = options.bin orelse b.path("node_modules/.bin/tailwindcss");
    const input = options.input orelse b.path("app/assets/styles.css");
    const output = options.output orelse b.path("{outdir}/assets/styles.css");

    const cmd: *std.Build.Step.Run = .create(b, "tailwind");
    cmd.addFileArg(bin);

    cmd.addArg("-i");
    cmd.addFileArg(input);

    cmd.addArg("-o");
    cmd.addFileArg(output);

    // This option is available with the tailwindcss CLI, but since zig watch already handles it we are not allowing it
    // if (options.watch) |watch| {
    //     switch (watch) {
    //         .enabled => cmd.addArg("--watch"),
    //         .always => cmd.addArg("--watch=always"),
    //     }
    // }

    if (options.minify) {
        cmd.addArg("--minify");
    }

    if (options.optimize) {
        cmd.addArg("--optimize");
    }

    if (options.cwd) |cwd| {
        cmd.addArg("--cwd");
        cmd.addFileArg(cwd);
    }

    if (options.map) {
        cmd.addArg("--map");
    }

    const steps = b.allocator.alloc(ZxInitOptions.PluginOptions.PluginStep, 1) catch @panic("OOM");
    steps[0] = .{
        .command = .{
            .type = .after_transpile,
            .run = cmd,
        },
    };

    return .{
        .name = "tailwindcss",
        .steps = steps,
    };
}

const std = @import("std");
const LazyPath = std.Build.LazyPath;

const TailwindPluginOptions = struct {
    /// Path to the tailwindcss binary [default: `node_modules/.bin/tailwindcss`]
    bin: ?LazyPath = null,
    /// Input file [default: `app/assets/styles.css`]
    input: ?LazyPath = null,
    /// Output file [default: `{outdir}/assets/styles.css`]
    /// `{outdir}/assets` means you can add link the styles like
    /// ```html
    /// <link rel="stylesheet" href="/assets/styles.css" />
    /// ```
    output: ?LazyPath = null,

    // watch: ?enum { enabled, always } = null, // This option is available with the tailwindcss CLI, but since zig watch already handles it we are not allowing it

    /// Optimize and minify the output
    minify: bool = false,
    /// Optimize the output without minifying
    optimize: bool = false,
    /// The current working directory [default: `.`]
    cwd: ?LazyPath = null,
    /// Generate a source map [default: `false`]
    map: bool = false,
};

const ZxInitOptions = @import("../init/ZxInitOptions.zig");
