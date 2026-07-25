const zx_info = @import("zx_info");

const context = @import("shared/context.zig");
const cli_args = @import("root.zig");

const CommandContext = context.CommandContext;
pub const command = cli_args.version;

pub fn run(ctx: CommandContext, args: anytype) !void {
    _ = args;
    try ctx.writer.print("{s}\n", .{zx_info.version});
}
