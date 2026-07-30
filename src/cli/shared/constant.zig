const std = @import("std");

pub const ziex_cache_dirname = "ziex";
pub const transpile_store_dirname = "tnsn";
pub const default_transpile_dir = std.fmt.comptimePrint("{f}", .{std.fs.path.fmtJoin(
    &.{ ".zig-cache", ziex_cache_dirname, transpile_store_dirname },
)});
pub const default_manifest_relpath = std.fmt.comptimePrint("{f}", .{
    std.fs.path.fmtJoin(&.{ "manifest", "app.zon" }),
});
