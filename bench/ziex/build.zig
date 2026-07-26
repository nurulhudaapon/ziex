const std = @import("std");
const ziex = @import("ziex");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const app_exe = b.addExecutable(.{
        .name = "ziex_app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("app/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{},
        }),
    });

    var zx_builder = try ziex.init(b, app_exe, .{
        .cli = .{ .optimize = .debug },
        .app = .{
            .features = .{
                // .sqlite = .enabled,
            },
            .client = .{
                .bindings = .{
                    .build = .enabled,
                },
            },
        },
    });
    zx_builder = zx_builder;
}
