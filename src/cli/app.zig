const std = @import("std");
const std_cli = @import("std_cli");

const asset = @import("app/asset.zig");
const context = @import("shared/context.zig");
const cli_args = @import("root.zig");

const CommandContext = context.CommandContext;
pub const command = cli_args.app;

pub fn run(ctx: CommandContext, parsed: anytype) !void {
    const sub = parsed.subcommand orelse {
        try std_cli.writeHelpGenerated(command, "zx", parsed, ctx.writer);
        return;
    };
    switch (sub) {
        .asset => |s| switch (s.kind) {
            .help => try std_cli.writeHelpGenerated(cli_args.@"app.asset", "zx", s, ctx.writer),
            .args => |args| try asset.run(ctx, args),
        },
    }
}
