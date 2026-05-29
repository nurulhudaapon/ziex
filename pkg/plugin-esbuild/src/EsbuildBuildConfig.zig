/// Zig-side config for an esbuild build.
/// Fields that accept LazyPath are resolved to strings before JSON serialization.
/// This struct is what callers fill in; use `toJsonValue` to turn it into a JSON value
/// that `esbuild` (the runner exe) can consume.
const EsbuildBuildConfig = @This();

pub const Sourcemap = enum { none, linked, @"inline", external, both };
pub const Format = enum { esm, cjs, iife };
pub const Platform = enum { browser, node, neutral };

/// Entry point file paths. At least one is required.
entrypoints: []const std.Build.LazyPath,

/// Target platform [default: .browser]
platform: ?Platform = null,

/// Output format [default: inferred by esbuild]
format: ?Format = null,

/// Source map output [default: .none]
sourcemap: ?Sourcemap = null,

/// Bundle all dependencies into the output files [default: true]
bundle: ?bool = null,

/// Minify the output (all sub-options at once)
minify: ?bool = null,

/// External packages - not bundled (can use * wildcards)
external: []const []const u8 = &.{},

/// Public path prefix for asset URLs
public_path: ?[]const u8 = null,

/// Environment target(s) (e.g. esnext, es2017, chrome58)
target: []const []const u8 = &.{},

/// Define global constants. Each entry is `KEY` -> `VALUE` (VALUE already JSON-quoted if a string).
define: []const struct { key: []const u8, value: []const u8 } = &.{},

/// Enable code splitting (ESM only)
splitting: ?bool = null,

/// Resolve all lazy paths and serialize to a `std.json.Value` that the `esbuild`
/// runner can pass directly to esbuild's JS API.
pub fn toJsonValue(self: EsbuildBuildConfig, b: *std.Build, arena: std.mem.Allocator) !std.json.Value {
    var obj = std.json.ObjectMap.empty;

    // entrypoints - required array
    var eps = std.json.Array.init(arena);
    for (self.entrypoints) |lp| {
        try eps.append(.{ .string = lp.getPath(b) });
    }
    try obj.put(arena, "entrypoints", .{ .array = eps });

    if (self.platform) |v| try obj.put(arena, "platform", .{ .string = @tagName(v) });
    if (self.format) |v| try obj.put(arena, "format", .{ .string = @tagName(v) });
    if (self.sourcemap) |v| try obj.put(arena, "sourcemap", .{ .string = @tagName(v) });
    if (self.bundle) |v| try obj.put(arena, "bundle", .{ .bool = v });
    if (self.minify) |v| try obj.put(arena, "minify", .{ .bool = v });
    if (self.splitting) |v| try obj.put(arena, "splitting", .{ .bool = v });
    if (self.public_path) |v| try obj.put(arena, "publicPath", .{ .string = v });

    if (self.external.len > 0) {
        var arr = std.json.Array.init(arena);
        for (self.external) |e| try arr.append(.{ .string = e });
        try obj.put(arena, "external", .{ .array = arr });
    }

    if (self.target.len > 0) {
        var arr = std.json.Array.init(arena);
        for (self.target) |t| try arr.append(.{ .string = t });
        try obj.put(arena, "target", .{ .array = arr });
    }

    if (self.define.len > 0) {
        var def_obj = std.json.ObjectMap.empty;
        for (self.define) |d| try def_obj.put(arena, d.key, .{ .string = d.value });
        try obj.put(arena, "define", .{ .object = def_obj });
    }

    return .{ .object = obj };
}

const std = @import("std");
