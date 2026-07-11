/// Esbuild build config.
const EsbuildBuildConfig = @This();

const std = @import("std");

pub const Sourcemap = enum { none, linked, @"inline", external, both };
pub const Format = enum { esm, cjs, iife };
pub const Platform = enum { browser, node, neutral };

pub const Define = struct {
    key: []const u8,
    value: []const u8,
};

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
define: []const Define = &.{},

/// Enable code splitting (ESM only)
splitting: ?bool = null,
