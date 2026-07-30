const std = @import("std");
const zx = @import("zx");
const api = @import("../api.zig");
const data = @import("../data.zig");

pub var component_count: usize = 0;
pub var route_count: usize = 0;

var components_fetch_started = false;
var routes_fetch_started = false;
var data_allocator: ?std.mem.Allocator = null;

pub fn ensureCountsFetch(allocator: std.mem.Allocator) void {
    if (comptime zx.platform.isServer()) return;
    if (!data.loadSettings()) return;
    data_allocator = allocator;
    fetchComponentsCount(allocator);
    fetchRoutesCount(allocator);
}

fn fetchComponentsCount(allocator: std.mem.Allocator) void {
    if (comptime zx.platform.isServer()) return;
    if (components_fetch_started) return;
    const url = api.componentsUrl(allocator, false) orelse return;
    components_fetch_started = true;
    _ = zx.fetch(.wasm(&onFetchComponentsCount), allocator, url, .{ .method = .GET }) catch {};
}

fn fetchRoutesCount(allocator: std.mem.Allocator) void {
    if (comptime zx.platform.isServer()) return;
    if (routes_fetch_started) return;
    const url = api.routesMetaUrl(allocator) orelse return;
    routes_fetch_started = true;
    _ = zx.fetch(.wasm(&onFetchRoutesCount), allocator, url, .{ .method = .GET }) catch {};
}

fn onFetchComponentsCount(res: ?*zx.Fetch.Response, _: ?zx.Fetch.FetchError) void {
    const allocator = data_allocator orelse return;
    if (res) |r| {
        defer r.deinit();
        if (r.text()) |p| {
            const parsed = zx.util.zxon.parse(zx.util.devtool.ComponentSerializable, allocator, p, .{}) catch return;
            component_count = api.countSerializable(&parsed, 0);
        } else |_| {}
    }
    zx.client.rerender();
}

fn onFetchRoutesCount(res: ?*zx.Fetch.Response, _: ?zx.Fetch.FetchError) void {
    const allocator = data_allocator orelse return;
    if (res) |r| {
        defer r.deinit();
        if (r.text()) |p| {
            const parsed = zx.util.zxon.parse([]const api.AppRoute, allocator, p, .{}) catch return;
            route_count = parsed.len;
        } else |_| {}
    }
    zx.client.rerender();
}

pub fn componentCountLabel(allocator: std.mem.Allocator) []const u8 {
    return std.fmt.allocPrint(allocator, "{d}", .{component_count}) catch "0";
}

pub fn routeCountLabel(allocator: std.mem.Allocator) []const u8 {
    return std.fmt.allocPrint(allocator, "{d}", .{route_count}) catch "0";
}
