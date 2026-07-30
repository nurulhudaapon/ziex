const std = @import("std");
const build_options = @import("build_options");

const context = @import("shared/context.zig");
const cli_args = @import("root.zig");

const CommandContext = context.CommandContext;
pub const command = cli_args.lsp;

pub fn run(ctx: CommandContext, args: anytype) !void {
    if (comptime !build_options.enable_lsp) {
        try ctx.writer.writeAll(
            \\LSP support is not enabled in this build.
            \\Rebuild with: zig build -Dlsp=true
            \\
        );
        return;
    }
    try @import("../lsp/main.zig").run(ctx, args.message);
}
