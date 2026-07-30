const std = @import("std");
const zx = @import("zx");
const api = @import("../api.zig");
const data = @import("../data.zig");
const string = @import("../string.zig");

pub const AppRoute = api.AppRoute;

pub var routes: []const AppRoute = &[_]AppRoute{};
pub var inputvalue: []const u8 = "";
pub var inputvalue_owned: ?[]const u8 = null;

var fetched = false;
var data_allocator: ?std.mem.Allocator = null;

pub fn ensureFetched(allocator: std.mem.Allocator) void {
    if (comptime zx.platform.isServer()) return;
    if (fetched) return;
    if (!data.loadSettings()) return;
    data_allocator = allocator;
    const url = api.routesMetaUrl(allocator) orelse return;
    fetched = true;
    _ = zx.fetch(.wasm(&onFetchText), allocator, url, .{ .method = .GET }) catch {};
}

fn onFetchText(res: ?*zx.Fetch.Response, _: ?zx.Fetch.FetchError) void {
    const allocator = data_allocator orelse return;
    if (res) |r| {
        defer r.deinit();
        if (r.text()) |p| {
            routes = zx.util.zxon.parse([]const AppRoute, allocator, p, .{}) catch return;
        } else |_| {}
    }
    zx.client.rerender();
}

pub fn setSearch(value: ?[]const u8) void {
    data.adopt(&inputvalue_owned, &inputvalue, value, "");
}

pub fn getMethodTokenClass(method: []const u8) []const u8 {
    if (std.mem.eql(u8, method, "GET")) return "route-method-token method-get";
    if (std.mem.eql(u8, method, "POST")) return "route-method-token method-post";
    if (std.mem.eql(u8, method, "PUT")) return "route-method-token method-put";
    if (std.mem.eql(u8, method, "DELETE")) return "route-method-token method-delete";
    if (std.mem.eql(u8, method, "PATCH")) return "route-method-token method-patch";
    if (std.mem.eql(u8, method, "HEAD")) return "route-method-token method-head";
    if (std.mem.eql(u8, method, "OPTIONS")) return "route-method-token method-options";
    if (std.mem.eql(u8, method, "ANY")) return "route-method-token method-any";
    return "route-method-token";
}

pub fn routeMatchesSearch(route: AppRoute) bool {
    if (inputvalue.len == 0) return true;
    if (string.containsIgnoreCase(route.path, inputvalue)) return true;
    if (string.containsIgnoreCase(route.kind, inputvalue)) return true;
    for (route.methods) |method| {
        if (string.containsIgnoreCase(method, inputvalue)) return true;
    }
    return false;
}

pub fn getRouteItemClass(route: AppRoute) []const u8 {
    if (!routeMatchesSearch(route)) return "route-item route-item-hidden";
    return "route-item";
}

pub fn getRouteHref(allocator: std.mem.Allocator, path: []const u8) []const u8 {
    return api.routeHref(allocator, path);
}
