const std = @import("std");
const cli = @import("cli");
const builtin = @import("builtin");

const context = @import("shared/context.zig");
const tui = @import("../tui/main.zig");

const version = @import("version.zig");
const init = @import("init.zig");
const dev = @import("dev.zig");
const serve = @import("serve.zig");
const build_cmd = @import("build.zig");
const transpile = @import("transpile.zig");
const fmt = @import("fmt.zig");
const lsp = @import("lsp.zig");
const export_cmd = @import("export.zig");
const bundle = @import("bundle.zig");
const update = @import("update.zig");
const upgrade = @import("upgrade.zig");

const AppContext = context.AppContext;
const CommandContext = context.CommandContext;
const Spinner = tui.Spinner;

const commands = switch (builtin.os.tag) {
    .wasi, .freestanding => .{ version, transpile, fmt },
    else => .{ version, init, dev, serve, build_cmd, transpile, fmt, lsp, export_cmd, bundle, update, upgrade },
};

pub const root_command: cli.Command = .{
    .name = .zx,
    .help =
    \\Ziex is a framework for building web applications with Zig.
    \\
    ,
    .help_short = "Ziex framework CLI",
    .subcommands = blk: {
        var list: [commands.len]cli.Command = undefined;
        for (commands, 0..) |mod, i| list[i] = mod.command;
        const frozen = list;
        break :blk &frozen;
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

    const is_wasm = builtin.cpu.arch.isWasm();
    var spinner: if (is_wasm) void else Spinner = if (is_wasm) {} else .init(writer, reader, allocator, .{});
    defer if (!is_wasm) spinner.deinit();

    const ctx: CommandContext = .{
        .allocator = allocator,
        .writer = writer,
        .reader = reader,
        .spinner = if (is_wasm) {} else &spinner,
        .app = app,
    };

    switch (parsed.subcommand.?) {
        inline else => |s, tag| inline for (commands) |mod| {
            if (comptime std.mem.eql(u8, @tagName(mod.command.name), @tagName(tag))) {
                return mod.run(ctx, s.kind.args);
            }
        },
    }
}
