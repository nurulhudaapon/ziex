const std = @import("std");
const tailwindcss = @import("tailwindcss");

pub fn build(b: *std.Build) !void {
    const builds = try b.allocator.alloc(tailwindcss.Build, 3);
    for (0..3) |i| {
        builds[i] = .{
            .name = b.fmt("example-{d}", .{i}),
            .config = .{
                .input = b.path("styles.css"),
            },
        };
    }
    const outputs = tailwindcss.addBuilds(b, builds);
    for (outputs, 0..) |output, i| {
        const install = b.addInstallFile(output.file, b.fmt("dist/output-{d}.css", .{i}));
        b.default_step.dependOn(&install.step);
    }
}
