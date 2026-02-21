const Bun = @This();

pub fn init(ctx: plugin.PluginCtx(BunPluginOptions)) ZxInitOptions.PluginOptions {
    const options = ctx.options;
    const b = ctx.build;

    var cmd = b.addSystemCommand(&.{ "bun", options.sub_cmd });
    for (options.inputs) |input| {
        cmd.addFileArg(input);
        cmd.addFileInput(input);
    }

    if (options.outdir) |outdir| {
        cmd.addPrefixedDirectoryArg("--outdir=", outdir);
    }

    if (options.sourcemap) |sourcemap| {
        cmd.addArg("--sourcemap");
        cmd.addArg(@tagName(sourcemap));
    }

    const steps = b.allocator.alloc(ZxInitOptions.PluginOptions.PluginStep, 1) catch @panic("OOM");
    steps[0] = .{
        .command = .{
            .type = .after_transpile,
            .run = cmd,
        },
    };

    return .{
        .name = "bun",
        .steps = steps,
    };
}

const std = @import("std");
const builtin = @import("builtin");
const LazyPath = std.Build.LazyPath;

const BunPluginOptions = struct {
    pub const Sourcemap = enum { linked, @"inline", external, none };

    bin: ?LazyPath = null,
    sub_cmd: []const u8 = "build",
    inputs: []const LazyPath = &.{},
    outdir: ?LazyPath = null,
    sourcemap: ?Sourcemap = null,
};

const ZxInitOptions = @import("../init/ZxInitOptions.zig");
const plugin = @import("../plugins.zig");
