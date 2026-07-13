const std = @import("std");
const Build = @import("Build");
const hashing = @import("hashing.zig");

const Manifest = Build.Manifest;
const AddElementOptions = Build.AddElementOptions;

/// Build helper: content-hash a static asset, install it, and upsert the
/// corresponding manifest injection (wasm preload link or jsglue script tag).
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();

    var args = try init.minimal.args.iterateAllocator(allocator);
    defer args.deinit();
    _ = args.next(); // skip program name

    var manifest_in: ?[]const u8 = null;
    var manifest_out: ?[]const u8 = null;
    var positionals = std.array_list.Managed([]const u8).init(allocator);
    defer positionals.deinit();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--manifest-out")) {
            manifest_out = args.next() orelse return error.MissingManifestOutPath;
            continue;
        }
        try positionals.append(arg);
    }

    if (positionals.items.len < 4) return error.MissingSrcPath;
    const src_path = positionals.items[0];
    const dest_dir = positionals.items[1];
    const href_stem = positionals.items[2];
    manifest_in = positionals.items[3];
    const file_stem = if (positionals.items.len > 4) positionals.items[4] else "main";
    const file_ext = if (positionals.items.len > 5) positionals.items[5] else ".wasm";
    const injection_kind = if (positionals.items.len > 6) positionals.items[6] else "wasmlink";
    const clean_dest = positionals.items.len > 7 and std.mem.eql(u8, positionals.items[7], "clean");

    const manifest_out_path = manifest_out orelse return error.MissingManifestOutPath;

    const content = try std.Io.Dir.cwd().readFileAlloc(io, src_path, allocator, .unlimited);

    const hash_input = if (std.mem.eql(u8, file_ext, ".wasm"))
        try hashing.hashInput(allocator, content)
    else
        content;
    defer if (hash_input.ptr != content.ptr) allocator.free(hash_input);

    const hash_tag = hashing.contentTag(hash_input);

    if (std.fs.path.dirname(dest_dir)) |parent| {
        try std.Io.Dir.cwd().createDirPath(io, parent);
    }

    if (clean_dest) {
        try cleanGeneratedAssetsDir(io, dest_dir);
    }
    try std.Io.Dir.cwd().createDirPath(io, dest_dir);

    const dest_name = try std.fmt.allocPrint(allocator, "{s}.{s}{s}", .{ file_stem, &hash_tag, file_ext });
    const dest_path = try std.fs.path.join(allocator, &.{ dest_dir, dest_name });

    try std.Io.Dir.cwd().copyFile(src_path, std.Io.Dir.cwd(), dest_path, io, .{ .make_path = true });

    const href = try std.fmt.allocPrint(allocator, "{s}.{s}{s}", .{ href_stem, &hash_tag, file_ext });

    var manifest = try Manifest.init(io, allocator, manifest_in.?);
    defer manifest.deinit();

    if (std.mem.eql(u8, injection_kind, "script")) {
        try manifest.upsertJsglueInjection(.{
            .parent = .head,
            .position = .ending,
            .id = AddElementOptions.Id.jsglue,
            .element = .{
                .tag = .script,
                .attributes = &.{
                    .{ .name = "defer" },
                    .{ .name = "src", .value = href },
                },
            },
        });
    } else {
        try manifest.upsertWasmlinkInjection(.{
            .parent = .head,
            .position = .ending,
            .id = AddElementOptions.Id.wasmlink,
            .element = .{
                .tag = .link,
                .attributes = &.{
                    .{ .name = "id", .value = "__$wasmlink" },
                    .{ .name = "rel", .value = "preload" },
                    .{ .name = "as", .value = "fetch" },
                    .{ .name = "href", .value = href },
                    .{ .name = "crossorigin" },
                },
            },
        });
    }

    try manifest.commitTo(io, manifest_out_path);
}

fn cleanGeneratedAssetsDir(io: std.Io, dest_dir: []const u8) !void {
    std.Io.Dir.cwd().deleteTree(io, dest_dir) catch {};
}
