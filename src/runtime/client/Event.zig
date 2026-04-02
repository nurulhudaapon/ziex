//! Client-side Event — wraps a browser JS event object.
//!
//! Provides DOM event methods: `value()`, `key()`, `preventDefault()`.
//! For state access, use `Event.Stateful` via `ctx.bind()`.

const std = @import("std");
const zx = @import("../../root.zig");
const pltfm = @import("../../platform.zig");
const client = @import("window.zig");
const reactivity = client.reactivity;

const platform_role = pltfm.platform.role;
const gpa = if (@import("builtin").os.tag == .freestanding) std.heap.wasm_allocator else std.heap.page_allocator;

const Event = @This();

/// The JS event object reference (as a u64 NaN-boxed value)
event_ref: u64,

pub fn init(event_ref: u64) Event {
    return .{ .event_ref = event_ref };
}

/// Get the underlying js.Object for the event
pub fn getEvent(self: Event) client.Event {
    return client.Event.fromRef(self.event_ref);
}

/// Get the underlying js.Object with data loaded (value, key, etc)
pub fn getEventWithData(self: Event, allocator: std.mem.Allocator) client.Event {
    return client.Event.fromRefWithData(allocator, self.event_ref);
}

pub fn preventDefault(self: Event) void {
    self.getEvent().preventDefault();
}

/// Get the input value from event.target.value
pub fn value(self: Event) ?[]const u8 {
    if (platform_role != .client) return null;
    const real_js = @import("js");
    const event = self.getEvent();
    const target = event.ref.get(real_js.Object, "target") catch return null;
    return target.getAlloc(real_js.String, gpa, "value") catch null;
}

/// Get the key from keyboard event
pub fn key(self: Event) ?[]const u8 {
    if (platform_role != .client) return null;
    const real_js = @import("js");
    const event = self.getEvent();
    return event.ref.getAlloc(real_js.String, gpa, "key") catch null;
}


// --- Stateful --- //

/// Stateful client event — provides `state()` access to bound component state.
/// Use `fn(*zx.client.Event.Stateful) void` with `ctx.bind()` to get this type.
pub const Stateful = struct {
    _inner: *Event,
    _component_id: []const u8 = "",
    _state_index: u32 = 0,

    /// Access the component's state.
    /// Must be called in the same order as `ctx.state()` in the render function.
    pub fn state(self: *Stateful, comptime T: type) *reactivity.State(T) {
        const slot = (1 << 20) + self._state_index;
        self._state_index += 1;
        return reactivity.State(T).getExisting(self._component_id, slot);
    }

    pub fn getEvent(self: Stateful) client.Event {
        return self._inner.getEvent();
    }

    pub fn getEventWithData(self: Stateful, allocator: std.mem.Allocator) client.Event {
        return self._inner.getEventWithData(allocator);
    }

    pub fn preventDefault(self: Stateful) void {
        self._inner.preventDefault();
    }

    pub fn value(self: Stateful) ?[]const u8 {
        return self._inner.value();
    }

    pub fn key(self: Stateful) ?[]const u8 {
        return self._inner.key();
    }

};
