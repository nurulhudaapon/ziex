pub fn main() !void {
    if (builtin.os.tag == .windows) _ = std.os.windows.kernel32.SetConsoleOutputCP(65001);

    var dbg = std.heap.DebugAllocator(.{}).init;

    const allocator = switch (builtin.mode) {
        .Debug => dbg.allocator(),
        .ReleaseFast, .ReleaseSafe, .ReleaseSmall => std.heap.smp_allocator,
    };

    defer if (builtin.mode == .Debug) std.debug.assert(dbg.deinit() == .ok);

    var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
    var stdout = &stdout_writer.interface;

    var buf: [4096]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().readerStreaming(&buf);
    const stdin = &stdin_reader.interface;

    const root = try cli.build(stdout, stdin, allocator);
    defer root.deinit();

    root.execute(.{}) catch |err| {
        const c = tui.Colors;
        const err_name = @errorName(err);
        const base_url = std.fmt.comptimePrint("{s}/issues/new", .{zx.info.repository});
        var url_buf: [512]u8 = undefined;
        const full_url = std.fmt.bufPrint(&url_buf, "{s}?title=CLI%20Error:%20{s}&body=**Error:**%20{s}%0A**Version:**%20{s}", .{
            base_url,
            err_name,
            err_name,
            zx.info.version,
        }) catch base_url;
        // OSC 8 hyperlink: \x1b]8;;URL\x07DISPLAY_TEXT\x1b]8;;\x07
        std.debug.print("\n{s}An unexpected problem occurred while running ZX CLI.{s}\n", .{ c.red, c.reset });
        std.debug.print("Please report it at {s}\x1b]8;;{s}\x07{s}\x1b]8;;\x07{s}\n", .{ c.cyan, full_url, base_url, c.reset });
        std.debug.print("{s}Details: {s}{s}\n\n", .{ c.gray, err_name, c.reset });
    };

    try stdout.flush();
}

const std = @import("std");
const cli = @import("cli/root.zig");
const builtin = @import("builtin");
const zx = @import("zx");
const tui = @import("tui/main.zig");

pub const std_options = std.Options{
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .@"html/ast", .level = .info },
        .{ .scope = .@"html/tokenizer", .level = .info },
        .{ .scope = .@"html/ast/fmt", .level = .info },
        .{ .scope = .ast, .level = if (builtin.mode == .Debug) .info else .warn },
        .{ .scope = .cli, .level = if (builtin.mode == .Debug) .info else .info },
    },
};
