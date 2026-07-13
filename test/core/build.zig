const std = @import("std");
const Build = @import("zx").Build;
const AddElementOptions = Build.AddElementOptions;

test "AddElementOptions.Pathname matches" {
    const all: AddElementOptions.Pathname = .{};
    try std.testing.expect(all.matches("/"));
    try std.testing.expect(all.matches("/docs"));

    const includes_only: AddElementOptions.Pathname = .{ .includes = &.{ "/docs", "/blog*" } };
    try std.testing.expect(includes_only.matches("/docs"));
    try std.testing.expect(includes_only.matches("/blog"));
    try std.testing.expect(includes_only.matches("/blog/post"));
    try std.testing.expect(!includes_only.matches("/"));

    const excludes: AddElementOptions.Pathname = .{ .excludes = &.{"/playground*"} };
    try std.testing.expect(excludes.matches("/"));
    try std.testing.expect(!excludes.matches("/playground"));
    try std.testing.expect(!excludes.matches("/playground/foo"));

    const both: AddElementOptions.Pathname = .{
        .includes = &.{"/examples*"},
        .excludes = &.{"/examples/secret"},
    };
    try std.testing.expect(both.matches("/examples"));
    try std.testing.expect(both.matches("/examples/api"));
    try std.testing.expect(!both.matches("/examples/secret"));
    try std.testing.expect(!both.matches("/docs"));
}
