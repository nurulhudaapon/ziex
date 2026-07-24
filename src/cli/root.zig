pub const root_command: cli.Command = .{
    .name = .zx,
    .help =
    \\Ziex is a framework for building web applications with Zig.
    \\
    ,
    .help_short = "Ziex framework CLI",
    .subcommands = &.{
        version.command,
        init.command,
        dev.command,
        serve.command,
        build_cmd.command,
        transpile.command,
        fmt.command,
        @"export".command,
        bundle.command,
        update.command,
        upgrade.command,
    },
};

pub fn run(
    writer: *std.Io.Writer,
    reader: *std.Io.Reader,
    allocator: std.mem.Allocator,
    args: []const [:0]const u8,
    app: *AppContext,
) !void {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const parsed = try cli.parseAlloc(root_command, arena, args, .{
        .exit_usage_error = true,
        .render_usage_errors = true,
        .exit_help = true,
        .render_help = .generated,
    });

    if (parsed.kind == .help or parsed.subcommand == null) {
        try cli.writeHelpGenerated(root_command, args[0], parsed, writer);
        return;
    }

    var spinner = Spinner.init(writer, reader, allocator, .{});
    defer spinner.deinit();

    const ctx: CommandContext = .{
        .allocator = allocator,
        .writer = writer,
        .reader = reader,
        .spinner = &spinner,
        .app = app,
    };

    switch (parsed.subcommand.?) {
        .version => |sub| try version.run(ctx, sub.kind.args),
        .init => |sub| try init.run(ctx, sub.kind.args),
        .dev => |sub| try dev.run(ctx, sub.kind.args),
        .serve => |sub| try serve.run(ctx, sub.kind.args),
        .build => |sub| try build_cmd.run(ctx, sub.kind.args),
        .transpile => |sub| try transpile.run(ctx, sub.kind.args),
        .fmt => |sub| try fmt.run(ctx, sub.kind.args),
        .@"export" => |sub| try @"export".run(ctx, sub.kind.args),
        .bundle => |sub| try bundle.run(ctx, sub.kind.args),
        .update => |sub| try update.run(ctx, sub.kind.args),
        .upgrade => |sub| try upgrade.run(ctx, sub.kind.args),
    }
}

const version = @import("version.zig");
const init = @import("init.zig");
const dev = @import("dev.zig");
const serve = @import("serve.zig");
const build_cmd = @import("build.zig");
const transpile = @import("transpile.zig");
const fmt = @import("fmt.zig");
const @"export" = @import("export.zig");
const bundle = @import("bundle.zig");
const update = @import("update.zig");
const upgrade = @import("upgrade.zig");

const std = @import("std");
const cli = @import("cli");
const Spinner = @import("../tui/main.zig").Spinner;
const context = @import("shared/context.zig");
const AppContext = context.AppContext;
const CommandContext = context.CommandContext;
