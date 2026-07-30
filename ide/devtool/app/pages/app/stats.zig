const std = @import("std");
const zx = @import("zx");
const api = @import("../api.zig");
const data = @import("../data.zig");
const connection = @import("../connection.zig");

pub var component_count: usize = 0;
pub var route_count: usize = 0;

var components_fetch_started = false;
var routes_fetch_started = false;
var data_allocator: ?std.mem.Allocator = null;

pub fn invalidate() void {
    components_fetch_started = false;
    routes_fetch_started = false;
    component_count = 0;
    route_count = 0;
}

pub fn ensureCountsFetch(allocator: std.mem.Allocator) void {
    if (comptime zx.platform.isServer()) return;
    if (!data.loadSettings()) return;
    _ = connection.applyUrlConfig(allocator);
    data_allocator = allocator;
    fetchComponentsCount(allocator);
    fetchRoutesCount(allocator);
}

fn fetchComponentsCount(allocator: std.mem.Allocator) void {
    if (comptime zx.platform.isServer()) return;
    if (components_fetch_started) return;
    const url = api.componentsUrl(allocator, false) orelse return;
    components_fetch_started = true;
    connection.markLoading();
    _ = zx.fetch(.wasm(&onFetchComponentsCount), allocator, url, .{ .method = .GET }) catch {
        connection.markUnavailable("Could not start request to the app.");
        return;
    };
}

fn fetchRoutesCount(allocator: std.mem.Allocator) void {
    if (comptime zx.platform.isServer()) return;
    if (routes_fetch_started) return;
    const url = api.routesMetaUrl(allocator) orelse return;
    routes_fetch_started = true;
    connection.markLoading();
    _ = zx.fetch(.wasm(&onFetchRoutesCount), allocator, url, .{ .method = .GET }) catch {
        connection.markUnavailable("Could not start request to the app.");
        return;
    };
}

fn onFetchComponentsCount(res: ?*zx.Fetch.Response, err: ?zx.Fetch.FetchError) void {
    const allocator = data_allocator orelse return;
    if (res) |r| {
        defer r.deinit();
        if (r.status >= 400) {
            connection.markUnavailable(if (r.status == 502)
                "No app is running on this host (dev server returned 502)."
            else
                "App returned an error while loading components.");
            zx.client.rerender();
            return;
        }
        if (r.text()) |p| {
            const parsed = zx.util.zxon.parse(zx.util.devtool.ComponentSerializable, allocator, p, .{}) catch {
                connection.markUnavailable("App responded, but the component payload was invalid.");
                zx.client.rerender();
                return;
            };
            component_count = api.countSerializable(&parsed, 0);
            connection.markConnected();
        } else |_| {
            connection.markUnavailable("Empty response from the app.");
        }
    } else {
        _ = err;
        if (connection.mixedContentHint(allocator)) |hint| {
            connection.markUnavailable(hint);
        } else {
            connection.markUnavailable("Cannot reach the app. Check the host/port, or start it with `zx dev` / `zig build dev`.");
        }
    }
    zx.client.rerender();
}

fn onFetchRoutesCount(res: ?*zx.Fetch.Response, err: ?zx.Fetch.FetchError) void {
    const allocator = data_allocator orelse return;
    if (res) |r| {
        defer r.deinit();
        if (r.status >= 400) {
            if (!connection.isUnavailable()) {
                connection.markUnavailable(if (r.status == 502)
                    "No app is running on this host (dev server returned 502)."
                else
                    "App returned an error while loading routes.");
            }
            zx.client.rerender();
            return;
        }
        if (r.text()) |p| {
            const parsed = zx.util.zxon.parse([]const api.AppRoute, allocator, p, .{}) catch return;
            route_count = parsed.len;
            if (!connection.isUnavailable()) connection.markConnected();
        } else |_| {}
    } else {
        _ = err;
        if (!connection.isUnavailable()) {
            if (connection.mixedContentHint(allocator)) |hint| {
                connection.markUnavailable(hint);
            } else {
                connection.markUnavailable("Cannot reach the app. Check the host/port, or start it with `zx` / `ziex`.");
            }
        }
    }
    zx.client.rerender();
}

pub fn componentCountLabel(allocator: std.mem.Allocator) []const u8 {
    return std.fmt.allocPrint(allocator, "{d}", .{component_count}) catch "0";
}

pub fn routeCountLabel(allocator: std.mem.Allocator) []const u8 {
    return std.fmt.allocPrint(allocator, "{d}", .{route_count}) catch "0";
}
