const std = @import("std");
const zx = @import("zx");

pub fn build(b: *std.Build) !void {
    const exe = b.addExecutable(.{ .name = "my-app" });

    var zx_build = try zx.init(b, exe, .{});

    var assetsdir = zx_build.assetsdir;
    zx_build.addPlugin(
        zx.plugins.tailwind(b, .{
            .input = b.path("app/assets/style.css"),
            .output = assetsdir.path(b, "style.css"),
        }),
    );
}
