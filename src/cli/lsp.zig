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
    const zx_module = if (args.@"zx-module".len > 0) args.@"zx-module" else null;
    try @import("../lsp/main.zig").run(ctx, .{
        .messages = args.message,
        .zx_module = zx_module,
    });
}
