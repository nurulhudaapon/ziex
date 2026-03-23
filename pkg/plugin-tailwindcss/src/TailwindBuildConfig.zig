/// Zig-side config for a Tailwind CSS build.
/// Fields that accept LazyPath are resolved to strings before JSON serialization.
const TailwindBuildConfig = @This();

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

pub fn toJsonValue(self: TailwindBuildConfig, b: *std.Build, arena: std.mem.Allocator) !std.json.Value {
    var obj = std.json.ObjectMap.init(arena);

    try obj.put("input", .{ .string = self.input.getPath(b) });
    try obj.put("minify", .{ .bool = self.minify });
    try obj.put("optimize", .{ .bool = self.optimize });
    try obj.put("map", .{ .bool = self.map });

    if (self.base) |base| try obj.put("base", .{ .string = base.getPath(b) });

    return .{ .object = obj };
}

const std = @import("std");
