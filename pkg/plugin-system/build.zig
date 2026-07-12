const std = @import("std");

pub const ExcludeFields = @import("src/exclude_fields.zig").ExcludeFields;
pub const options = @import("src/exclude_fields.zig").options;
pub const writeDepFile = @import("src/dep_file.zig").writeDepFile;
pub const colors = @import("src/colors.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("plugin_system", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
}
