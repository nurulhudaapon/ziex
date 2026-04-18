//! Client-side Event - wraps a browser JS event object.
//!
//! Provides DOM event methods: `value()`, `key()`, `preventDefault()`.
//! For state access, use `Event.Stateful` via `ctx.bind()`.

const std = @import("std");
const zx = @import("../../root.zig");
const pltfm = @import("../../platform.zig");
const client = @import("window.zig");
const generated_events = @import("events_generated.zig");
const reactivity = client.reactivity;

const platform_role = pltfm.platform.role;
const gpa = if (@import("builtin").os.tag == .freestanding) std.heap.wasm_allocator else std.heap.page_allocator;
pub const Kind = generated_events.Kind;

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

/// Get the event data by providing zx.client.events.<Type>.
pub fn as(self: Event, comptime T: type, allocator: std.mem.Allocator) T {
    if (platform_role != .client) return std.mem.zeroInit(T, .{});
    return readStruct(T, allocator, self.getEvent().ref);
}

pub fn data(self: Event, comptime kind: Kind, allocator: std.mem.Allocator) Data(kind) {
    return self.as(Data(kind), allocator);
}

pub const Data = generated_events.Data;

fn readStruct(comptime T: type, allocator: std.mem.Allocator, obj: @import("js").Object) T {
    const info = @typeInfo(T).@"struct";
    var result: T = std.mem.zeroInit(T, .{});
    inline for (info.fields) |field| {
        if (readField(field.type, allocator, obj, field.name)) |v| {
            @field(result, field.name) = v;
        }
    }
    return result;
}

fn readField(comptime F: type, allocator: std.mem.Allocator, obj: @import("js").Object, comptime name: []const u8) ?F {
    const real_js = @import("js");
    const finfo = @typeInfo(F);
    const Child = if (finfo == .optional) finfo.optional.child else F;
    const child_info = @typeInfo(Child);
    const raw = obj.value.get(name) catch return null;
    defer raw.deinit();

    const raw_type = raw.typeOf();
    if (raw_type == .null or raw_type == .undefined) return null;

    switch (child_info) {
        .@"struct" => {
            if (raw_type != .object and raw_type != .function) return null;
            const sub = real_js.Object{ .value = raw };
            return readStruct(Child, allocator, sub);
        },
        .pointer => |p| {
            if (p.size == .slice and p.child == u8) {
                if (raw_type != .string) return null;
                return raw.string(allocator) catch null;
            }
            @compileError("unsupported pointer field type in Event.as: " ++ @typeName(F));
        },
        .int, .float => {
            if (raw_type != .number) return null;
            if (child_info == .int) {
                return @as(Child, @intFromFloat(raw.float() catch return null));
            }
            return @as(Child, @floatCast(raw.float() catch return null));
        },
        .bool => {
            if (raw_type != .boolean) return null;
            return raw.boolean() catch null;
        },
        else => @compileError("unsupported field type in Event.as: " ++ @typeName(F)),
    }
}

// --- Stateful --- //

/// Stateful client event - provides `state()` access to bound component state.
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

    pub fn as(self: Stateful, comptime T: type, allocator: std.mem.Allocator) T {
        return self._inner.as(T, allocator);
    }

    pub fn data(self: Stateful, comptime kind: Kind, allocator: std.mem.Allocator) Data(kind) {
        return self._inner.data(kind, allocator);
    }
};
