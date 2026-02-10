const std = @import("std");
const zx = @import("zx");

pub fn build(b: *std.Build) !void {
    const exe = b.addExecutable(.{ .name = "my-site" });

    try zx.init(b, exe, .{
        .plugins = &.{
            zx.plugins.tailwind(b, .{
                .input = b.path("app/assets/styles.css"),
                .output = b.path("{outdir}/assets/styles.css"),
            }),
        },
    });
}
