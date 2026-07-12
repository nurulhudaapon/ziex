/// Tailwind CSS build configuration
///
/// See [Tailwind CSS documentation](https://tailwindcss.com/docs/installation/using-postcss) for more information.
const TailwindBuildConfig = @This();

const std = @import("std");

/// Input CSS file path (required)
input: std.Build.LazyPath,

/// Minify the output [default: false]
minify: bool = false,

/// Optimize the output without full minification [default: false]
optimize: bool = false,

/// Generate a source map [default: false]
map: bool = false,

/// Base directory for resolving imports [default: dirname(input)]
base: ?std.Build.LazyPath = null,

/// Additional source file paths to scan for class names
sources: []const std.Build.LazyPath = &.{},
