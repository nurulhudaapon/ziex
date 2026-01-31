//! Browser Object Model (BOM) bindings for client-side JavaScript interop.
//! These types provide Zig interfaces to browser APIs like console, events, and document.
//! On server builds, these types exist but their methods are no-ops.

const std = @import("std");
const builtin = @import("builtin");
const ext = @import("window/extern.zig");

/// Whether we're running in a browser environment (WASM)
pub const is_wasm = builtin.cpu.arch == .wasm32 or builtin.cpu.arch == .wasm64;

/// JS bindings - only available in WASM builds
const js = if (is_wasm) @import("js") else struct {
    pub const Object = void;
    pub const String = []const u8;
    pub const global = struct {
        pub fn get(_: type, _: []const u8) !void {}
        pub fn call(_: type, _: []const u8, _: anytype) !void {}
    };
    pub fn string(_: []const u8) void {}
};

pub const Console = struct {
    ref: if (is_wasm) @import("js").Object else void,

    pub fn init() Console {
        if (!is_wasm) return .{ .ref = {} };
        return .{
            .ref = @import("js").global.get(@import("js").Object, "console") catch @panic("Console not found"),
        };
    }

    pub fn deinit(self: Console) void {
        if (!is_wasm) return;
        self.ref.deinit();
    }

    pub fn log(self: Console, args: anytype) void {
        if (!is_wasm) return;
        self.ref.call(void, "log", args) catch @panic("Failed to call console.log");
    }

    pub fn str(self: Console, data: []const u8) void {
        if (!is_wasm) return;
        self.ref.call(void, "log", .{@import("js").string(data)}) catch @panic("Failed to call console.log");
    }

    pub fn strLevel(self: Console, message_level: std.log.Level, data: []const u8) void {
        if (!is_wasm) return;
        const j = @import("js");
        switch (message_level) {
            .debug => self.ref.call(void, "debug", .{j.string(data)}) catch @panic("Failed to call console.debug"),
            .info => self.ref.call(void, "info", .{j.string(data)}) catch @panic("Failed to call console.info"),
            .warn => self.ref.call(void, "warn", .{j.string(data)}) catch @panic("Failed to call console.warn"),
            .err => self.ref.call(void, "error", .{j.string(data)}) catch @panic("Failed to call console.error"),
        }
    }
};

pub const Event = struct {
    pub const EventTarget = struct {
        value: ?[]const u8 = null,
    };

    /// The js.Object reference to the event
    ref: if (is_wasm) @import("js").Object else void,

    target: ?EventTarget = null,
    data: ?[]const u8 = null,

    /// Create an Event from a u64 NaN-boxed reference (passed from JS via jsz)
    pub fn fromRef(event_ref: u64) Event {
        if (!is_wasm) return .{ .ref = {}, .target = null, .data = null };
        const real_js = @import("js");

        // Convert the u64 reference to a js.Value, then wrap in js.Object
        const event_value: real_js.Value = @enumFromInt(event_ref);
        const event_obj = real_js.Object{ .value = event_value };

        return .{
            .ref = event_obj,
            .target = null,
            .data = null,
        };
    }

    /// Create an Event from a u64 reference and load target/data properties
    pub fn fromRefWithData(allocator: std.mem.Allocator, event_ref: u64) Event {
        if (!is_wasm) return .{ .ref = {}, .target = null, .data = null };
        const real_js = @import("js");

        // Convert the u64 reference to a js.Value, then wrap in js.Object
        const event_value: real_js.Value = @enumFromInt(event_ref);
        const event_obj = real_js.Object{ .value = event_value };

        // Get target and its value
        const target: ?real_js.Object = event_obj.get(real_js.Object, "target") catch null;
        const target_value: ?[]const u8 = if (target) |t| t.getAlloc(real_js.String, allocator, "value") catch null else null;

        const event_target: ?EventTarget = if (target_value) |v| .{ .value = v } else null;
        const event_data: ?[]const u8 = event_obj.getAlloc(real_js.String, allocator, "data") catch null;

        return .{
            .ref = event_obj,
            .target = event_target,
            .data = event_data,
        };
    }

    /// Call preventDefault on the event
    pub fn preventDefault(self: Event) void {
        if (!is_wasm) return;
        self.ref.call(void, "preventDefault", .{}) catch @panic("Failed to call preventDefault");
    }

    /// Call stopPropagation on the event
    pub fn stopPropagation(self: Event) void {
        if (!is_wasm) return;
        self.ref.call(void, "stopPropagation", .{}) catch @panic("Failed to call stopPropagation");
    }

    /// Get the event type as a string
    pub fn getType(self: Event, allocator: std.mem.Allocator) ?[]const u8 {
        if (!is_wasm) return null;
        const real_js = @import("js");
        return self.ref.getAlloc(real_js.String, allocator, "type") catch null;
    }

    /// Get the target element (returns js.Object in WASM, void otherwise)
    pub fn getTarget(self: Event) if (is_wasm) ?@import("js").Object else ?void {
        if (!is_wasm) return null;
        const real_js = @import("js");
        return self.ref.get(real_js.Object, "target") catch null;
    }

    /// Deinit the event (releases the JS reference)
    pub fn deinit(self: Event) void {
        if (!is_wasm) return;
        self.ref.deinit();
    }
};

pub fn eval(T: type, code: []const u8) !T {
    // Use @as to "touch" the parameter and prevent unused warning
    _ = @as([]const u8, code);
    if (!is_wasm) return error.NotInBrowser;
    const real_js = @import("js");
    return try real_js.global.call(T, "eval", .{real_js.string(code)});
}

pub const Document = @import("window/document.zig");

// =============================================================================
// Async APIs: setTimeout, setInterval
// =============================================================================

/// Callback types for async operations (must match bridge.ts CallbackType)
pub const CallbackType = enum(u8) {
    event = 0,
    fetch_success = 1, // kept for compatibility with dispatchCallback
    fetch_error = 2, // kept for compatibility with dispatchCallback
    timeout = 3,
    interval = 4,
};

/// Callback function types
pub const TimeoutCallback = *const fn () void;
pub const IntervalCallback = *const fn () void;

/// Maximum number of concurrent callbacks
const MAX_CALLBACKS = 64;

/// Callback registry entry
const CallbackEntry = struct {
    callback_type: CallbackType,
    timeout_fn: ?TimeoutCallback = null,
    interval_fn: ?IntervalCallback = null,
    active: bool = false,
};

/// Global callback registry
var callbacks: [MAX_CALLBACKS]CallbackEntry = [_]CallbackEntry{.{
    .callback_type = .event,
    .active = false,
}} ** MAX_CALLBACKS;
var next_callback_id: u64 = 1;

/// Register a callback and get its ID
fn registerCallback(entry: CallbackEntry) ?u64 {
    const id = next_callback_id;
    const index: usize = @intCast(id % MAX_CALLBACKS);

    if (callbacks[index].active) {
        // Slot is occupied, find another
        for (&callbacks, 0..) |*slot, i| {
            if (!slot.active) {
                slot.* = entry;
                slot.active = true;
                next_callback_id = i + 1;
                return @intCast(i);
            }
        }
        return null; // No free slots
    }

    callbacks[index] = entry;
    callbacks[index].active = true;
    next_callback_id += 1;
    return id;
}

/// Set a timeout that calls the callback after delay_ms milliseconds
pub fn setTimeout(callback: TimeoutCallback, delay_ms: u32) ?u64 {
    if (!is_wasm) return null;

    const id = registerCallback(.{
        .callback_type = .timeout,
        .timeout_fn = callback,
        .active = true,
    }) orelse return null;

    ext._setTimeout(id, delay_ms);
    return id;
}

/// Set an interval that calls the callback every interval_ms milliseconds
pub fn setInterval(callback: IntervalCallback, interval_ms: u32) ?u64 {
    if (!is_wasm) return null;

    const id = registerCallback(.{
        .callback_type = .interval,
        .interval_fn = callback,
        .active = true,
    }) orelse return null;

    ext._setInterval(id, interval_ms);
    return id;
}

/// Clear an interval by its ID
pub fn clearInterval(callback_id: u64) void {
    if (!is_wasm) return;

    const index: usize = @intCast(callback_id % MAX_CALLBACKS);
    if (callbacks[index].active and callbacks[index].callback_type == .interval) {
        callbacks[index].active = false;
        ext._clearInterval(callback_id);
    }
}

/// Dispatch a callback from JS (called by __zx_cb export)
/// Returns true if a callback was found and invoked
pub fn dispatchCallback(callback_type: CallbackType, callback_id: u64, data_ref: u64, allocator: std.mem.Allocator) bool {
    _ = data_ref;
    _ = allocator;

    const index: usize = @intCast(callback_id % MAX_CALLBACKS);
    const entry = &callbacks[index];

    if (!entry.active) return false;

    switch (callback_type) {
        .timeout => {
            if (entry.timeout_fn) |cb| {
                cb();
                entry.active = false; // One-shot
                return true;
            }
        },
        .interval => {
            if (entry.interval_fn) |cb| {
                cb();
                // Keep active for next tick
                return true;
            }
        },
        .fetch_success, .fetch_error, .event => return false,
    }

    return false;
}

// =============================================================================
// WebSocket Client API (re-export from core)
// =============================================================================

/// Re-export the core WebSocket for client-side use
pub const WebSocket = @import("../core/WebSocket.zig");
