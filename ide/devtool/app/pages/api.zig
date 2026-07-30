const std = @import("std");
const zx = @import("zx");
const data = @import("data.zig");

pub const AppRoute = struct {
    path: []const u8,
    kind: []const u8 = "Page",
    methods: []const []const u8 = &.{},
    has_notfound: bool = false,
    is_dynamic: bool = false,
};

pub fn hostBaseUrl(allocator: std.mem.Allocator) ?[]const u8 {
    _ = data.loadSettings();
    const host = data.host;
    if (std.mem.startsWith(u8, host, "http://") or std.mem.startsWith(u8, host, "https://")) {
        return host;
    }
    return std.fmt.allocPrint(allocator, "http://{s}", .{host}) catch null;
}

pub fn componentsUrl(allocator: std.mem.Allocator, include_native: bool) ?[]const u8 {
    const base = hostBaseUrl(allocator) orelse return null;
    const path = data.current_path;
    if (include_native) {
        return std.fmt.allocPrint(allocator, "{s}/.well-known/_zx/devtool?path={s}&include_native=1", .{ base, path }) catch null;
    }
    return std.fmt.allocPrint(allocator, "{s}/.well-known/_zx/devtool?path={s}", .{ base, path }) catch null;
}

pub fn routesMetaUrl(allocator: std.mem.Allocator) ?[]const u8 {
    const base = hostBaseUrl(allocator) orelse return null;
    return std.fmt.allocPrint(allocator, "{s}/.well-known/_zx/devtool?meta=true", .{base}) catch null;
}

pub fn routeHref(allocator: std.mem.Allocator, path: []const u8) []const u8 {
    const base = hostBaseUrl(allocator) orelse return "#";
    return std.fmt.allocPrint(allocator, "{s}{s}", .{ base, path }) catch "#";
}

pub fn countSerializable(node: *const zx.util.devtool.ComponentSerializable, acc: usize) usize {
    var total = acc + 1;
    if (node.children) |kids| {
        for (kids) |*kid| {
            total = countSerializable(kid, total);
        }
    }
    return total;
}
