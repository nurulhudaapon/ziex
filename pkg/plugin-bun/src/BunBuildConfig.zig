/// Zig-side mirror of Bun.BuildConfig.
/// Fields that accept LazyPath are resolved to strings before JSON serialization.
/// This struct is what callers fill in; use `toJson` to turn it into a JSON value
/// that `bunjs` can consume.
const BunBuildConfig = @This();

pub const Sourcemap = enum { none, linked, @"inline", external };
pub const Format = enum { esm, cjs, iife };
pub const Target = enum { browser, bun, node };

/// Entry point file paths. At least one is required.
entrypoints: []const std.Build.LazyPath,

/// Target runtime [default: .browser]
target: ?Target = null,

/// Output format [default: .esm]
format: ?Format = null,

/// Source map output [default: .none]
sourcemap: ?Sourcemap = null,

/// Minify the output (all sub-options at once)
minify: ?bool = null,

/// External packages — not bundled
external: []const []const u8 = &.{},

/// Public path prefix for asset URLs
public_path: ?[]const u8 = null,

/// Define global constants. Each entry is `"KEY": "VALUE"` (already JSON-quoted value).
define: []const struct { key: []const u8, value: []const u8 } = &.{},

/// Enable code splitting (ESM only)
splitting: ?bool = null,

/// Resolve all lazy paths and serialize to a `std.json.Value` that `bunjs`
/// can pass directly as `Bun.BuildConfig`.
pub fn toJsonValue(self: BunBuildConfig, b: *std.Build, arena: std.mem.Allocator) !std.json.Value {
    var obj = std.json.ObjectMap.init(arena);

    // entrypoints — required array
    var eps = std.json.Array.init(arena);
    for (self.entrypoints) |lp| {
        try eps.append(.{ .string = lp.getPath(b) });
    }
    try obj.put("entrypoints", .{ .array = eps });

    if (self.target) |v| try obj.put("target", .{ .string = @tagName(v) });
    if (self.format) |v| try obj.put("format", .{ .string = @tagName(v) });
    if (self.sourcemap) |v| try obj.put("sourcemap", .{ .string = @tagName(v) });
    if (self.minify) |v| try obj.put("minify", .{ .bool = v });
    if (self.splitting) |v| try obj.put("splitting", .{ .bool = v });
    if (self.public_path) |v| try obj.put("publicPath", .{ .string = v });

    if (self.external.len > 0) {
        var arr = std.json.Array.init(arena);
        for (self.external) |e| try arr.append(.{ .string = e });
        try obj.put("external", .{ .array = arr });
    }

    if (self.define.len > 0) {
        var def_obj = std.json.ObjectMap.init(arena);
        for (self.define) |d| try def_obj.put(d.key, .{ .string = d.value });
        try obj.put("define", .{ .object = def_obj });
    }

    return .{ .object = obj };
}

const std = @import("std");
