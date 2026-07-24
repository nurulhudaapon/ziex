pub const command: cli.Command = .{
    .name = .version,
    .help_short = "Show CLI version",
};

pub fn run(ctx: CommandContext, args: anytype) !void {
    _ = args;
    try ctx.writer.print("{s}\n", .{zx_info.version});
}

const cli = @import("cli");
const zx_info = @import("zx_info");
const CommandContext = @import("shared/context.zig").CommandContext;
