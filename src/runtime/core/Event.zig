//! Shared Event types for both client-side and server-side event handlers.
//!
//! Both `zx.client.Event` and `zx.server.Event` share this state interface:
//!   - `Event.Stateful` - wrapper with `state()` for handlers bound via `ctx.bind()`
//!   - `StateHandle(T)` - returned by `state()`, provides `.get()` / `.set()`
//!   - `StateContext` - positional state accessor used internally by the bind wrappers

const std = @import("std");
const zx = @import("../../root.zig");

/// A handle to a single state value.
/// Returned by `e.state(T)` or `sc.state(T)` - call `.get()` to read, `.set(val)` to write back.
pub fn StateHandle(comptime T: type) type {
    return struct {
        _ctx: *StateContext,
        _index: usize,
        _value: T,

        pub fn get(self: @This()) T {
            return self._value;
        }

        pub fn set(self: @This(), val: T) void {
            if (self._index >= self._ctx._outputs.len) return;
            var aw = std.Io.Writer.Allocating.init(self._ctx._allocator);
            zx.util.zxon.serialize(val, &aw.writer, .{}) catch return;
            self._ctx._outputs[self._index] = aw.written();
        }
    };
}

/// Server-side accessor for component states round-tripped through a server event.
///
/// Call `sc.state(T)` in the same order as `ctx.state(T)` in the render function
/// to access each bound state - no index needed.
pub const StateContext = struct {
    arena: std.mem.Allocator,
    _allocator: std.mem.Allocator,
    /// Positional JSON values received from the client, one per bound state.
    _inputs: []const []const u8,
    /// Positional JSON values to return to the client (pre-seeded from _inputs).
    _outputs: [][]u8,
    /// Auto-incremented by each call to state().
    _index: usize = 0,

    /// Create a StateContext from raw state slices (e.g. from a server event payload or form data).
    /// Duplicates each input into `outputs` so unmodified states are preserved in the response.
    pub fn init(allocator: std.mem.Allocator, arena: std.mem.Allocator, inputs: []const []const u8) ?*StateContext {
        const outputs = allocator.alloc([]u8, inputs.len) catch return null;
        for (inputs, 0..) |s, i| {
            outputs[i] = allocator.dupe(u8, s) catch "";
        }
        const sc = allocator.create(StateContext) catch return null;
        sc.* = .{
            .arena = arena,
            ._allocator = allocator,
            ._inputs = inputs,
            ._outputs = outputs,
        };
        return sc;
    }

    /// Access the next bound state in call order, deserializing it to type `T`.
    /// Returns a StateHandle with `.get()` / `.set()` - same ergonomics as Event.Stateful.state().
    pub fn state(self: *StateContext, comptime T: type) StateHandle(T) {
        const i = self._index;
        self._index += 1;
        const val: T = if (i < self._inputs.len)
            zx.util.zxon.parse(T, self._allocator, self._inputs[i], .{}) catch std.mem.zeroes(T)
        else
            std.mem.zeroes(T);
        return StateHandle(T){ ._ctx = self, ._index = i, ._value = val };
    }

    pub fn fmt(self: StateContext, comptime format: []const u8, args: anytype) ![]u8 {
        var aw: std.Io.Writer.Allocating = .init(self.arena);
        defer aw.deinit();
        aw.writer.print(format, args) catch |err| switch (err) {
            error.WriteFailed => return error.OutOfMemory,
        };
        return aw.toOwnedSlice();
    }
};
