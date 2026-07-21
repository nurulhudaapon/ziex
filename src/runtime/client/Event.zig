const Event = @This();

const std = @import("std");
const builtin = @import("builtin");

const zx = @import("../../root.zig");
const client = @import("window.zig");
const generated_events = @import("events/generated.zig");

const js = zx.client.js;
const reactivity = client.reactivity;
const Allocator = zx.Allocator;
pub const Kind = generated_events.Kind;
const platform_role = zx.platform.role;

_internal: Internal = .{},

pub const Internal = struct {
    event_ref: u64 = 0,
    component_id: []const u8 = "",
    state_idx: u32 = 0,
};

pub fn init(event_ref: u64) Event {
    return .{ ._internal = .{ .event_ref = event_ref } };
}

/// Get the underlying js.Object for the event
pub fn getEvent(self: Event) client.Event {
    return client.Event.fromRef(self._internal.event_ref);
}

pub fn preventDefault(self: Event) void {
    self.getEvent().preventDefault();
}

pub fn stopPropagation(self: Event) void {
    self.getEvent().stopPropagation();
}

pub fn stopImmediatePropagation(self: Event) void {
    self.getEvent().stopImmediatePropagation();
}

/// Get the input/button value for the element that owns the handler.
/// Prefers `currentTarget` so nested children (e.g. spans inside a button)
/// still resolve the bound element's `value`.
pub fn value(self: Event) ?[]const u8 {
    if (platform_role != .client) return null;
    const event = self.getEvent();
    if (event.ref.get(js.Object, "currentTarget") catch null) |current| {
        defer current.deinit();
        if (current.getAlloc(js.String, zx.allocator, "value") catch null) |v| return v;
    }
    const target = event.ref.get(js.Object, "target") catch return null;
    defer target.deinit();
    return target.getAlloc(js.String, zx.allocator, "value") catch null;
}

/// Get the key from keyboard event
pub fn key(self: Event) ?[]const u8 {
    if (platform_role != .client) return null;
    const event = self.getEvent();
    return event.ref.getAlloc(js.String, zx.allocator, "key") catch null;
}

/// Get the event data by providing zx.client.events.<Type>.
pub fn as(self: Event, comptime T: type, allocator: Allocator) T {
    _ = allocator;
    if (platform_role != .client) return std.mem.zeroInit(T, .{});
    const event = self.getEvent();
    if (comptime (builtin.mode == .Debug)) assertType(T, event);
    return readStruct(T, scratchAllocator(), event.ref);
}

var scratch_arena: std.heap.ArenaAllocator = undefined;
var scratch_ready: bool = false;

fn scratchAllocator() Allocator {
    if (!scratch_ready) {
        scratch_arena = .init(zx.allocator);
        scratch_ready = true;
    } else {
        _ = scratch_arena.reset(.retain_capacity);
    }
    return scratch_arena.allocator();
}

/// Debug-only guard: validates that requested struct `T` matches the live event.
inline fn assertType(comptime T: type, event: client.Event) void {
    if (comptime T == generated_events.Event) return;

    const type_str = event.getType(zx.allocator) orelse return;
    defer zx.allocator.free(type_str);

    const kind = generated_events.kindForType(type_str) orelse return; // custom event
    switch (kind) {
        inline else => |k| {
            if (generated_events.Data(k) != T) {
                std.log.err(
                    \\Event.as, incorrect type requested for '{s}' event
                    \\
                    \\  Requested: {s}
                    \\  Expected: {s}
                    \\
                ,
                    .{ type_str, @typeName(T), @typeName(generated_events.Data(k)) },
                );
            }
        },
    }
}

// const Data = generated_events.Data;
// pub fn data(self: Event, comptime kind: Kind, allocator: Allocator) Data(kind) {
//     return self.as(Data(kind), allocator);
// }

fn readStruct(comptime T: type, allocator: Allocator, obj: js.Object) T {
    const info = @typeInfo(T).@"struct";
    var result: T = std.mem.zeroInit(T, .{});
    inline for (info.field_types, info.field_names) |field_type, field_name| {
        if (readField(field_type, allocator, obj, field_name)) |v| {
            @field(result, field_name) = v;
        }
    }
    return result;
}

fn readField(comptime F: type, allocator: Allocator, obj: js.Object, comptime name: []const u8) ?F {
    const finfo = @typeInfo(F);
    const Child = if (finfo == .optional) finfo.optional.child else F;
    const child_info = @typeInfo(Child);
    const js_name = comptime generated_events.jsName(name);
    const raw = obj.value.get(js_name) catch return null;
    defer raw.deinit();

    const raw_type = raw.typeOf();
    if (raw_type == .null or raw_type == .undefined) return null;

    switch (child_info) {
        .@"struct" => {
            if (raw_type != .object and raw_type != .function) return null;
            const sub = js.Object{ .value = raw };
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
pub const Stateful = struct {
    inner: *Event,

    /// Access the component's state.
    /// Must be called in the same order as `ctx.state()` in the render function.
    pub fn state(self: *Stateful, comptime T: type) *reactivity.State(T) {
        const slot = (1 << 20) + self.inner._internal.state_idx;
        self.inner._internal.state_idx += 1;
        return reactivity.State(T).getExisting(self.inner._internal.component_id, slot);
    }

    pub fn getEvent(self: Stateful) client.Event {
        return self.inner.getEvent();
    }

    pub fn preventDefault(self: Stateful) void {
        self.inner.preventDefault();
    }

    pub fn stopPropagation(self: Stateful) void {
        self.inner.stopPropagation();
    }

    pub fn stopImmediatePropagation(self: Stateful) void {
        self.inner.stopImmediatePropagation();
    }

    pub fn value(self: Stateful) ?[]const u8 {
        return self.inner.value();
    }

    pub fn key(self: Stateful) ?[]const u8 {
        return self.inner.key();
    }

    pub fn as(self: Stateful, comptime T: type, allocator: Allocator) T {
        return self.inner.as(T, allocator);
    }

    // pub fn data(self: Stateful, comptime kind: Kind, allocator: Allocator) Data(kind) {
    //     return self.inner.data(kind, allocator);
    // }
};
