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
    const code = @embedFile("overview.zx");
    var tree = try zx.Parse.parse(allocator, code);
    defer tree.deinit(allocator);

    const root_node = tree.tree.rootNode();
    std.debug.print("Root node: {s}\n", .{root_node.kind()});

    var rendered_zx = try tree.renderAllocWithSourceMap(allocator, .zig, true);
    defer rendered_zx.deinit(allocator);
    std.debug.print("Rendered ZX: {s}\n", .{rendered_zx.output});

    const source_map_json = try rendered_zx.source_map.?.toJSON(allocator, "overview.zig", "overview.zx", code, rendered_zx.output);
    defer allocator.free(source_map_json);
    std.debug.print("Sourcemap: {s}\n", .{source_map_json});

    try std.fs.cwd().writeFile(.{
        .sub_path = "src/overview.zig",
        .data = rendered_zx.output,
    });

    try std.fs.cwd().writeFile(.{
        .sub_path = "src/overview.zx.map.json",
        .data = source_map_json,
    });

    const rendered_zx_zx = try tree.renderAlloc(allocator, .zx);
    defer allocator.free(rendered_zx_zx);
    std.debug.print("Rendered ZX: {s}\n", .{rendered_zx_zx});

    try std.fs.cwd().writeFile(.{
        .sub_path = "src/overview.fmt.zx",
        .data = rendered_zx_zx,
    });

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
