const std = @import("std");
const zx = @import("zx");

pub fn build(b: *std.Build) !void {
    // --- Target and Optimize from `zig build` arguments ---
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- ZX App Executable ---
    const app_exe = b.addExecutable(.{
        .name = "zx_app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("app/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // --- ZX setup: wires dependencies and adds `zx`/`dev` build steps ---
    var zx_build = try zx.init(b, app_exe, .{});

    // HACK: on wasi we do not inject jsglue automatically yet
    if (target.result.os.tag == .wasi)
        zx_build.addElement(.{
            .parent = .body,
            .position = .ending,
            .element = .{
                .tag = "script",
                .attributes = "src=\"https://cdn.jsdelivr.net/npm/ziex@0.1.0-dev.804/wasm/init.min.js\"",
            },
        });
}
