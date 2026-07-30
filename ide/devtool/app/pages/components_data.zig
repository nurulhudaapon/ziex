const std = @import("std");
const zx = @import("zx");
const api = @import("api.zig");
const data = @import("data.zig");

pub var components: []const data.Component = &.{};
pub var inputvalue: []const u8 = "";
pub var inputvalue_owned: ?[]const u8 = null;
pub var stateFilter: []const u8 = "";
pub var stateFilter_owned: ?[]const u8 = null;
pub var selected_component: []const u8 = "0";
pub var selected_component_owned: ?[]const u8 = null;

var fetched = false;
var data_allocator: ?std.mem.Allocator = null;

pub fn ensureFetched(allocator: std.mem.Allocator) void {
    if (comptime zx.platform.isServer()) return;
    if (fetched) return;
    if (!data.loadSettings()) return;
    data_allocator = allocator;
    const url = api.componentsUrl(allocator, true) orelse return;
    fetched = true;
    _ = zx.fetch(.wasm(&onFetchText), allocator, url, .{ .method = .GET }) catch {};
}

fn onFetchText(res: ?*zx.Fetch.Response, _: ?zx.Fetch.FetchError) void {
    const allocator = data_allocator orelse return;
    if (res) |r| {
        defer r.deinit();
        if (r.text()) |p| {
            const parsed = zx.util.zxon.parse(zx.util.devtool.ComponentSerializable, allocator, p, .{}) catch return;
            const mapped = data.fromSerializableRoot(allocator, parsed) catch unreachable;
            std.log.info("Fetched {d} root components", .{mapped.len});
            components = mapped;
        } else |_| {}
    }
    zx.client.rerender();
}

pub fn setSearch(value: ?[]const u8) void {
    data.adopt(&inputvalue_owned, &inputvalue, value, "");
}

pub fn setStateFilter(value: ?[]const u8) void {
    data.adopt(&stateFilter_owned, &stateFilter, value, "");
}

pub fn setSelected(value: ?[]const u8) void {
    data.adopt(&selected_component_owned, &selected_component, value, "0");
}

pub fn toggleTreeCollapsed() void {
    data.tree_collapsed = !data.tree_collapsed;
    data.saveSettings();
}
