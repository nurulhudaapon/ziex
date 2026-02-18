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
    bin: ?LazyPath = null,
    sub_cmd: []const u8 = "build",
    inputs: []const LazyPath = &.{},
    outdir: ?LazyPath = null,
};

const ZxInitOptions = @import("../init/ZxInitOptions.zig");
const plugin = @import("../plugins.zig");
