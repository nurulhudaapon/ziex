pub fn tailwind(options: TailwindPluginOptions) ZxInitOptions.PluginOptions {
    _ = options;
    return .{
        .name = "tailwindcss",
        .steps = &.{
            .{
                .command = .{
                    .type = .after_transpile,
                    .args = &.{
                        "site/node_modules/.bin/tailwindcss",
                        // "--optimize",
                        // "--minify",
                        "--map",
                        "-i",
                        "site/styles.css",
                        "-o",
                        "{outdir}/assets/styles.css",
                    },
                },
            },
        },
    };
}

const TailwindPluginOptions = struct {
    inputs: ?[]const []const u8 = null,
    outputs: ?[]const []const u8 = null,
};

const ZxInitOptions = @import("../init/ZxInitOptions.zig").ZxInitOptions;
