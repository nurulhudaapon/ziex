const std = @import("std");
const zx = @import("../../root.zig");

pub const ActionFn = *const fn (*zx.server.Action) void;
pub const ServerEventFn = *const fn (*zx.server.Event) void;

var mu: std.Thread.Mutex = .{};
var map: std.StringHashMap(ActionFn) = undefined;
var event_map: std.StringHashMap(ServerEventFn) = undefined;
var initialized = false;

fn ensureInit() void {
    if (initialized) return;
    map = std.StringHashMap(ActionFn).init(std.heap.page_allocator);
    event_map = std.StringHashMap(ServerEventFn).init(std.heap.page_allocator);
    initialized = true;
}

/// Register an action handler for a route. Route paths are comptime-stable
/// string literals so no duplication of the key is needed.
pub fn register(route_path: []const u8, action_fn: ActionFn) void {
    mu.lock();
    defer mu.unlock();
    ensureInit();
    map.put(route_path, action_fn) catch {};
}

pub fn registerEvent(route_path: []const u8, handler_id: u32, event_fn: ServerEventFn) void {
    mu.lock();
    defer mu.unlock();
    ensureInit();

    // Composite key: "route_path:component_name:handler_id"
    var buf: [1024]u8 = undefined;
    const key = std.fmt.bufPrint(&buf, "{s}:{d}", .{ route_path, handler_id }) catch return;
    const key_dupe = std.heap.page_allocator.dupe(u8, key) catch return;

    event_map.put(key_dupe, event_fn) catch {};
}

pub fn getEvent(route_path: []const u8, handler_id: u32) ?ServerEventFn {
    mu.lock();
    defer mu.unlock();

    // std.debug.print("GETTING SERVER EVENT: [{s}:{d}]\n", .{ route_path, handler_id });
    // All infos initialiation, and list of current keys
    // var it = event_map.keyIterator();
    // while (it.next()) |key| {
    //     std.debug.print("KEY: {s}\n", .{key.*});
    // }
    if (!initialized) return null;

    var buf: [1024]u8 = undefined;
    const key = std.fmt.bufPrint(&buf, "{s}:{d}", .{ route_path, handler_id }) catch return null;

    return event_map.get(key);
}

/// Look up a registered action handler by route path.
pub fn get(route_path: []const u8) ?ActionFn {
    mu.lock();
    defer mu.unlock();
    if (!initialized) return null;
    return map.get(route_path);
}
