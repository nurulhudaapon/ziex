//! Server-side Event - context for server event handlers.
//!
//! Provides the event payload value via `value()`.
//! For state access, use `Event.Stateful` via `ctx.bind()`.

const std = @import("std");
const zx = @import("../../root.zig");
const core = @import("../core/Event.zig");
const Allocator = std.mem.Allocator;
const StateContext = core.StateContext;

const Event = @This();

allocator: Allocator = undefined,
arena: Allocator = undefined,
action_ref: u64 = 0,
payload: zx.EventHandler.Payload = .{},
/// Set by the comptime-generated wrapper when the handler uses StateContext.
_state_ctx: ?*StateContext = null,

pub fn init(action_ref: u64) Event {
    return .{ .action_ref = action_ref };
}

pub fn value(self: Event) ?[]const u8 {
    return self.payload.value;
}

/// Stateful server event - provides `state()` access to bound component state.
/// Use `fn(*zx.server.Event.Stateful) void` with `ctx.bind()` to get this type.
pub const Stateful = struct {
    _inner: *Event,
    _state_ctx: *StateContext,

    /// Access the component's state (server-side).
    /// Must be called in the same order as `ctx.state()` in the render function.
    pub fn state(self: *Stateful, comptime T: type) core.StateHandle(T) {
        return self._state_ctx.state(T);
    }

    pub fn value(self: Stateful) ?[]const u8 {
        return self._inner.value();
    }
};
