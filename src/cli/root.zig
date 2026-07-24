const std = @import("std");
const builtin = @import("builtin");
const cli = @import("cli");
const Spinner = @import("../tui/main.zig").Spinner;
const context = @import("shared/context.zig");
const AppContext = context.AppContext;
const CommandContext = context.CommandContext;

const version = @import("version.zig");
const transpile = @import("transpile.zig");
const fmt = @import("fmt.zig");

/// Host-only commands need process/thread APIs unavailable on WASI.
const is_wasm = builtin.os.tag == .wasi or builtin.os.tag == .freestanding;

pub const root_command: cli.Command = .{
    .name = .zx,
    .help =
    \\Ziex is a framework for building web applications with Zig.
    \\
    ,
    .help_short = "Ziex framework CLI",
    .subcommands = if (is_wasm) &.{
        version.command,
        transpile.command,
        fmt.command,
    } else &.{
        version.command,
        @import("init.zig").command,
        @import("dev.zig").command,
        @import("serve.zig").command,
        @import("build.zig").command,
        transpile.command,
        fmt.command,
        @import("export.zig").command,
        @import("bundle.zig").command,
        @import("update.zig").command,
        @import("upgrade.zig").command,
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

    if (comptime is_wasm) {
        switch (parsed.subcommand.?) {
            .version => |sub| try version.run(ctx, sub.kind.args),
            .transpile => |sub| try transpile.run(ctx, sub.kind.args),
            .fmt => |sub| try fmt.run(ctx, sub.kind.args),
        }
    } else {
        switch (parsed.subcommand.?) {
            .version => |sub| try version.run(ctx, sub.kind.args),
            .init => |sub| try @import("init.zig").run(ctx, sub.kind.args),
            .dev => |sub| try @import("dev.zig").run(ctx, sub.kind.args),
            .serve => |sub| try @import("serve.zig").run(ctx, sub.kind.args),
            .build => |sub| try @import("build.zig").run(ctx, sub.kind.args),
            .transpile => |sub| try transpile.run(ctx, sub.kind.args),
            .fmt => |sub| try fmt.run(ctx, sub.kind.args),
            .@"export" => |sub| try @import("export.zig").run(ctx, sub.kind.args),
            .bundle => |sub| try @import("bundle.zig").run(ctx, sub.kind.args),
            .update => |sub| try @import("update.zig").run(ctx, sub.kind.args),
            .upgrade => |sub| try @import("upgrade.zig").run(ctx, sub.kind.args),
        }
    }
}
