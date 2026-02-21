pub fn plugin(ctx: p.PluginCtx(PluginArgs)) !void {
    _ = ctx;
}

pub const PluginArgs = struct {
    @"--bundle": bool,
    variadic: bool,
};
pub const options: PluginOptions = .{
    .name = "bun",
};

const PluginOptions = struct {
    name: []const u8,
};

const p = @import("../../plugins.zig");
