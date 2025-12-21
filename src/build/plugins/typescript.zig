// TODO: Plugin should always be a file with main() function that receiveds standaridized args
// Maybe there can be stdio mode where files will be provided in zon format line by line
pub fn typescript(options: ReactPluginOptions) ZxInitOptions.PluginOptions {
    _ = options;

    const is_debug = builtin.mode == .Debug;

    return .{
        .name = "typescript",
        .steps = &.{
            // .{
            //     .command = .{
            //         .type = .after_transpile,
            //         .args = &.{
            //             "bun",
            //             "install",
            //         },
            //     },
            // },
            .{
                .command = .{
                    .type = .after_transpile,
                    .args = &.{
                        "site/node_modules/.bin/esbuild",
                        "site/main.ts",
                        "--bundle",
                        if (!is_debug) "--minify" else "--sourcemap=inline",
                        if (!is_debug) "--define:__DEV__=false" else "--define:__DEV__=true",
                        if (!is_debug)
                            "--define:process.env.NODE_ENV=\"production\""
                        else
                            "--define:process.env.NODE_ENV=\"development\"",
                        "--outfile=site/.zx/assets/main.js",
                        "--log-level=silent",
                    },
                },
            },
        },
    };
}

const builtin = @import("builtin");

const ReactPluginOptions = struct {};

const ZxInitOptions = @import("../init/ZxInitOptions.zig");
