const std = @import("std");
const zx = @import("zx");
const api = @import("api.zig");
const data = @import("data.zig");
const connection = @import("connection.zig");

pub var components: []const data.Component = &.{};
pub var inputvalue: []const u8 = "";
pub var inputvalue_owned: ?[]const u8 = null;
pub var stateFilter: []const u8 = "";
pub var stateFilter_owned: ?[]const u8 = null;
pub var selected_component: []const u8 = "";
pub var selected_component_owned: ?[]const u8 = null;

var fetched = false;
var data_allocator: ?std.mem.Allocator = null;

pub fn invalidate() void {
    fetched = false;
    components = &.{};
}

pub fn ensureFetched(allocator: std.mem.Allocator) void {
    if (comptime zx.platform.isServer()) return;
    if (fetched) return;
    if (!data.loadSettings()) return;
    _ = connection.applyUrlConfig(allocator);
    data_allocator = allocator;
    const url = api.componentsUrl(allocator, true) orelse return;
    fetched = true;
    connection.markLoading();
    _ = zx.fetch(.wasm(&onFetchText), allocator, url, .{ .method = .GET }) catch {
        connection.markUnavailable("Could not start request to the app.");
        return;
    };
}

fn onFetchText(res: ?*zx.Fetch.Response, err: ?zx.Fetch.FetchError) void {
    const allocator = data_allocator orelse return;
    if (res) |r| {
        defer r.deinit();
        if (r.status >= 400) {
            connection.markUnavailable(unavailableReason(allocator, r.status));
            zx.client.rerender();
            return;
        }
        if (r.text()) |p| {
            const parsed = zx.util.zxon.parse(zx.util.devtool.ComponentSerializable, allocator, p, .{}) catch {
                connection.markUnavailable("App responded, but the component payload was invalid.");
                zx.client.rerender();
                return;
            };
            const mapped = data.fromSerializableRoot(allocator, parsed) catch {
                connection.markUnavailable("Failed to map component tree.");
                zx.client.rerender();
                return;
            };
            std.log.info("Fetched {d} root components", .{mapped.len});
            components = mapped;
            connection.markConnected();
        } else |_| {
            connection.markUnavailable("Empty response from the app.");
        }
    } else {
        _ = err;
        connection.markUnavailable(connection.defaultUnavailableReason(allocator));
    }
    zx.client.rerender();
}

fn unavailableReason(allocator: std.mem.Allocator, status_code: u16) []const u8 {
    _ = allocator;
    return switch (status_code) {
        502 => "No app is running on this host (dev server returned 502).",
        else => "App returned an error while loading components.",
    };
}

pub fn setSearch(value: ?[]const u8) void {
    data.adopt(&inputvalue_owned, &inputvalue, value, "");
}

pub fn setStateFilter(value: ?[]const u8) void {
    data.adopt(&stateFilter_owned, &stateFilter, value, "");
}

pub fn setSelected(value: ?[]const u8) void {
    data.adopt(&selected_component_owned, &selected_component, value, "");
}

pub fn toggleTreeCollapsed() void {
    data.tree_collapsed = !data.tree_collapsed;
    data.saveSettings();
}
