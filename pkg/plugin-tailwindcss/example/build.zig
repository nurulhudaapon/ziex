const std = @import("std");
const tailwindcss = @import("tailwindcss");

pub fn build(b: *std.Build) !void {
    const builds = try b.allocator.alloc(tailwindcss.Build, 3);
    for (0..3) |i| {
        builds[i] = .{
            .name = b.fmt("example-{d}", .{i}),
            .config = .{
                .input = b.path("styles.css"),
                .output = b.path(b.fmt("dist/output-{d}.css", .{i})),
            },
        };
    }
    tailwindcss.addBuildsRun(b, builds);
}
