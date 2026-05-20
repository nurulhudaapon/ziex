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

/// Additional source file paths to scan for class names
sources: ?[]const std.Build.LazyPath = null,

pub fn toJsonValue(self: TailwindBuildConfig, b: *std.Build, arena: std.mem.Allocator) !std.json.Value {
    var obj = std.json.ObjectMap.empty;

    try obj.put(arena, "input", .{ .string = self.input.getPath(b) });
    try obj.put(arena, "minify", .{ .bool = self.minify });
    try obj.put(arena, "optimize", .{ .bool = self.optimize });
    try obj.put(arena, "map", .{ .bool = self.map });

    if (self.base) |base| try obj.put(arena, "base", .{ .string = base.getPath(b) });

    if (self.sources) |sources| {
        var arr = try std.json.Array.initCapacity(arena, sources.len);
        for (sources) |source| {
            arr.appendAssumeCapacity(.{ .string = source.getPath(b) });
        }
        try obj.put(arena, "sources", .{ .array = arr });
    }

    return .{ .object = obj };
}

const std = @import("std");
