pub fn main() !void {
    if (builtin.os.tag == .windows) {
        _ = std.os.windows.kernel32.SetConsoleOutputCP(65001);
    }

    var dbg = std.heap.DebugAllocator(.{}).init;

    const allocator = switch (@import("builtin").mode) {
        .Debug => dbg.allocator(),
        .ReleaseFast, .ReleaseSafe, .ReleaseSmall => std.heap.smp_allocator,
    };

    defer if (@import("builtin").mode == .Debug) std.debug.assert(dbg.deinit() == .ok);

    var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
    var stdout = &stdout_writer.interface;

    var buf: [4096]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().readerStreaming(&buf);
    const stdin = &stdin_reader.interface;

    const root = try cli.build(stdout, stdin, allocator);
    defer root.deinit();

    // ----
    // const parser = zx.Parse;
    // var tree = try parser.parse(allocator, "pub fn main(    ) !void {}");
    // defer tree.deinit(allocator);

    // const root_node = tree.tree.rootNode();
    // std.debug.print("Root node: {s}\n", .{root_node.kind()});

    // const rendered_zx = try tree.renderAlloc(allocator, .zx);
    // defer allocator.free(rendered_zx);
    // std.debug.print("Rendered ZX: {s}\n", .{rendered_zx});

    // const res = url.URL.parse("https://www.google.com");
    // std.debug.print("URL: {s}\n", .{res.href});
    // ----

    try root.execute(.{});

    try stdout.flush();
}

const std = @import("std");
const cli = @import("cli/root.zig");
const builtin = @import("builtin");
const zx = @import("zx");

pub const std_options = std.Options{
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .@"html/ast", .level = .info },
        .{ .scope = .@"html/tokenizer", .level = .info },
        .{ .scope = .@"html/ast/fmt", .level = .info },
        .{ .scope = .ast, .level = if (builtin.mode == .Debug) .info else .warn },
        .{ .scope = .cli, .level = if (builtin.mode == .Debug) .info else .info },
    },
};
