pub fn react(options: ReactPluginOptions) ZxInitOptions.PluginOptions {
    _ = options;

    //     const esbuild_bin_path = std.fs.path.join(ctx.allocator, &.{ pkg_rootdir, "node_modules", ".bin", "esbuild" }) catch return error.EsbuildBinNotFound;
    // defer ctx.allocator.free(esbuild_bin_path);
    // var esbuild_args = std.ArrayList([]const u8).empty;
    // try esbuild_args.append(ctx.allocator, esbuild_bin_path);
    // try esbuild_args.append(ctx.allocator, main_tsx_argz);
    // try esbuild_args.append(ctx.allocator, "--bundle");
    // if (!is_dev) try esbuild_args.append(ctx.allocator, "--minify");
    // try esbuild_args.append(ctx.allocator, outfile_arg);
    // if (is_dev) try esbuild_args.append(ctx.allocator, "--define:process.env.NODE_ENV=\"development\"") else try esbuild_args.append(ctx.allocator, "--define:process.env.NODE_ENV=\"production\"");
    // if (is_dev) try esbuild_args.append(ctx.allocator, "--define:__DEV__=true") else try esbuild_args.append(ctx.allocator, "--define:__DEV__=false");

    return .{
        .name = "react",
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
                        "--minify",
                        "--define:process.env.NODE_ENV=\"production\"",
                        "--define:__DEV__=false",
                        "--outfile=site/.zx/assets/main.js",
                        "--log-level=silent",
                    },
                },
            },
        },
    };
}

const ReactPluginOptions = struct {
    package_json_path: ?[]const u8 = null,
};

const ZxInitOptions = @import("../init/ZxInitOptions.zig").ZxInitOptions;
