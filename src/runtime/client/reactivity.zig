//! Reactive primitives for client-side state management.
//! Provides fine-grained reactivity where only DOM nodes that depend on
//! changed signals are updated (no full re-render or tree diffing).

const std = @import("std");
const builtin = @import("builtin");

const Client = @import("Client.zig");
const zx = @import("../../root.zig");
const js = zx.client.js;

const BindingList = std.ArrayList(js.Object);
const EffectList = std.ArrayList(EffectCallback);

var signal_bindings = std.ArrayList(BindingList).empty;
var effect_callbacks = std.ArrayList(EffectList).empty;
var next_signal_id: u64 = 0;

const is_wasm = builtin.os.tag == .freestanding;
const allocator = zx.client_allocator;

pub fn signal(comptime T: type, initial: T) Signal(T) {
    return Signal(T).init(initial);
}

pub fn Signal(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const ValueType = T;

        id: u64,
        value: T,
        runtime_id_assigned: bool = false,
        instance_idx: u32 = 0,

        pub fn init(initial: T) Self {
            return .{ .id = 0, .value = initial, .runtime_id_assigned = false };
        }

        pub fn initWithId(initial: T, id: u64) Self {
            return .{ .id = id, .value = initial, .runtime_id_assigned = id != 0 };
        }

        pub fn ensureId(self: anytype) void {
            const mutable = @constCast(self);
            if (!mutable.runtime_id_assigned) {
                mutable.id = next_signal_id;
                next_signal_id += 1;
                mutable.runtime_id_assigned = true;
            }
        }

        pub inline fn get(self: *const Self) T {
            return self.value;
        }

        pub inline fn ptr(self: *Self) *T {
            return &self.value;
        }

        pub fn set(self: *Self, new_value: T) void {
            self.value = new_value;
            self.notifyChange();
        }

        pub fn update(self: *Self, comptime updater: fn (T) T) void {
            self.value = updater(self.value);
            self.notifyChange();
        }

        pub fn notifyChange(self: *const Self) void {
            updateSignalNodes(self.id, self.value);
            runEffects(self.id);
        }

        pub inline fn eql(self: *const Self, other: T) bool {
            return std.meta.eql(self.value, other);
        }

        pub fn format(self: *const Self, buf: []u8) []const u8 {
            return formatValue(T, self.value, buf);
        }

        // ============ Instance-based signal creation for ComponentCtx ============
        var instances = std.ArrayList(*Self).empty;
        var initial_values = std.ArrayList(T).empty;

        /// Instance handle returned by create() - acts like Signal but with handler generation.
        pub const ComponentSignal = struct {
            signal: *Self,

            /// Get the current value
            pub inline fn get(self: ComponentSignal) T {
                return self.signal.get();
            }

            /// Set a new value
            pub inline fn set(self: ComponentSignal, new_value: T) void {
                self.signal.set(new_value);
            }

            /// Format for template rendering
            pub fn format(self: ComponentSignal, buf: []u8) []const u8 {
                return self.signal.format(buf);
            }

            /// Get a handler to reset to initial value
            pub fn reset(self: ComponentSignal) zx.EventHandler {
                return .{
                    .callback = &struct {
                        fn handler(ctx: *anyopaque, _: zx.EventContext) void {
                            const sig_ptr: *Self = @ptrCast(@alignCast(ctx));
                            sig_ptr.set(initial_values.items[sig_ptr.instance_idx]);
                        }
                    }.handler,
                    .context = self.signal,
                };
            }

            /// Create an event handler that updates the signal using a transform function.
            /// Usage: `<button onclick={count.bind(struct { fn f(x: i32) i32 { return x + 1; } }.f)}>+</button>`
            pub fn bind(self: ComponentSignal, comptime transform: *const fn (T) T) zx.EventHandler {
                return .{
                    .callback = &struct {
                        fn handler(ctx: *anyopaque, _: zx.EventContext) void {
                            const sig_ptr: *Self = @ptrCast(@alignCast(ctx));
                            sig_ptr.set(transform(sig_ptr.get()));
                        }
                    }.handler,
                    .context = self.signal,
                };
            }
        };

        /// Create an instance-aware signal for use in ComponentCtx.
        /// Each instance ID gets its own independent storage.
        pub fn create(instance_id: u16, initial: T) !ComponentSignal {
            const idx = @as(usize, instance_id);

            if (idx >= instances.items.len) {
                try instances.ensureTotalCapacity(allocator, idx + 1);
                while (instances.items.len <= idx) {
                    const new_instance_ptr = try allocator.create(Self);
                    new_instance_ptr.* = Self.init(undefined);
                    try instances.append(allocator, new_instance_ptr);
                    try initial_values.append(allocator, undefined);
                }
            }

            instances.items[idx].* = Self.init(initial);
            instances.items[idx].instance_idx = @intCast(idx);
            initial_values.items[idx] = initial;

            return .{
                .signal = instances.items[idx],
            };
        }
    };
}

/// Top-level alias for Signal(T).Instance to improve IDE/ZLS type resolution.
pub fn SignalInstance(comptime T: type) type {
    return Signal(T).ComponentSignal;
}

fn formatValue(comptime T: type, value: T, buf: []u8) []const u8 {
    return switch (@typeInfo(T)) {
        .int, .comptime_int => std.fmt.bufPrint(buf, "{d}", .{value}) catch "?",
        .float, .comptime_float => std.fmt.bufPrint(buf, "{d:.2}", .{value}) catch "?",
        .bool => if (value) "true" else "false",
        .pointer => |ptr_info| blk: {
            if (ptr_info.size == .slice and ptr_info.child == u8) {
                break :blk value;
            }
            break :blk std.fmt.bufPrint(buf, "{any}", .{value}) catch "?";
        },
        .@"enum" => @tagName(value),
        .optional => if (value) |v| formatValue(@TypeOf(v), v, buf) else "",
        else => std.fmt.bufPrint(buf, "{any}", .{value}) catch "?",
    };
}

fn updateSignalNodes(signal_id: u64, value: anytype) void {
    if (!is_wasm) return;
    const T = @TypeOf(value);
    const idx = @as(usize, @intCast(signal_id));
    if (idx >= signal_bindings.items.len) return;
    const count = signal_bindings.items[idx].items.len;

    if (count == 0) return;

    var buf: [256]u8 = undefined;
    const text = formatValue(T, value, &buf);

    for (signal_bindings.items[idx].items) |node| {
        node.set("nodeValue", js.string(text)) catch {};
    }
}

/// Check if a type is a Signal type.
pub fn isSignalType(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info == .pointer) {
        const Child = info.pointer.child;
        if (@typeInfo(Child) == .@"struct") {
            return @hasField(Child, "id") and
                @hasField(Child, "value") and
                @hasDecl(Child, "get") and
                @hasDecl(Child, "set") and
                @hasDecl(Child, "notifyChange");
        }
    }
    return false;
}

/// Get the value type from a Signal pointer type.
pub fn SignalValueType(comptime T: type) type {
    const info = @typeInfo(T);
    if (info == .pointer) {
        const Child = info.pointer.child;
        if (@typeInfo(Child) == .@"struct" and @hasField(Child, "value")) {
            return @FieldType(Child, "value");
        }
    }
    @compileError("Expected a pointer to a Signal type");
}

/// Derived/computed value that updates when its source signal changes.
pub fn Computed(comptime T: type, comptime SourceT: type) type {
    return struct {
        const Self = @This();
        pub const ValueType = T;

        id: u64 = 0,
        runtime_id_assigned: bool = false,
        value: T = undefined,
        initialized: bool = false,
        source: *const Signal(SourceT),
        compute: *const fn (SourceT) T,
        subscribed: bool = false,

        pub fn init(source: *const Signal(SourceT), compute: *const fn (SourceT) T) Self {
            return .{
                .id = 0,
                .runtime_id_assigned = false,
                .value = undefined,
                .initialized = false,
                .source = source,
                .compute = compute,
                .subscribed = false,
            };
        }

        pub fn ensureId(self: anytype) void {
            const mutable = @constCast(self);
            if (!mutable.runtime_id_assigned) {
                mutable.id = next_signal_id;
                next_signal_id += 1;
                mutable.runtime_id_assigned = true;
            }
        }

        fn ensureInitialized(self: anytype) void {
            const mutable = @constCast(self);
            if (!mutable.initialized) {
                mutable.value = mutable.compute(mutable.source.get());
                mutable.initialized = true;
            }
        }

        pub fn subscribe(self: *Self) void {
            if (self.subscribed) return;
            self.ensureInitialized();
            self.source.ensureId();
            registerEffect(self.source.id, @ptrCast(self), updateWrapper);
            self.subscribed = true;
        }

        fn updateWrapper(ctx: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.recompute();
        }

        fn recompute(self: *Self) void {
            const new_value = self.compute(self.source.get());
            self.value = new_value;
            updateSignalNodes(self.id, new_value);
            runEffects(self.id);
        }

        pub fn get(self: anytype) T {
            const mutable = @constCast(self);
            mutable.subscribe();
            mutable.ensureInitialized();
            return mutable.value;
        }

        pub fn notifyChange(self: *const Self) void {
            updateSignalNodes(self.id, self.value);
        }
    };
}

const EffectCallback = struct {
    context: *anyopaque,
    run_fn: *const fn (*anyopaque) void,
};

/// Register a text node binding for a signal (no-op on server).
pub fn registerBinding(signal_id: u64, text_node: js.Object) void {
    if (!is_wasm) return;
    ensureSignalSlot(signal_id) catch return;
    const idx = @as(usize, @intCast(signal_id));
    signal_bindings.items[idx].append(allocator, text_node) catch {};
}

/// Clear all bindings for a signal (no-op on server).
pub fn clearBindings(signal_id: u64) void {
    if (!is_wasm) return;
    const idx = @as(usize, @intCast(signal_id));
    if (idx >= signal_bindings.items.len) return;

    for (signal_bindings.items[idx].items) |node| {
        node.deinit();
    }
    signal_bindings.items[idx].clearRetainingCapacity();
}

/// Register an effect callback for a signal.
pub fn registerEffect(signal_id: u64, context: *anyopaque, run_fn: *const fn (*anyopaque) void) void {
    ensureSignalSlot(signal_id) catch return;
    const idx = @as(usize, @intCast(signal_id));
    effect_callbacks.items[idx].append(allocator, .{ .context = context, .run_fn = run_fn }) catch {};
}

fn runEffects(signal_id: u64) void {
    const idx = @as(usize, @intCast(signal_id));
    if (idx >= effect_callbacks.items.len) return;

    for (effect_callbacks.items[idx].items) |cb| {
        cb.run_fn(cb.context);
    }
}

/// Reset global reactivity state (useful for testing).
pub fn reset() void {
    if (is_wasm) {
        for (signal_bindings.items) |*list| {
            list.deinit(allocator);
        }
        signal_bindings.clearAndFree(allocator);
    }
    for (effect_callbacks.items) |*list| {
        list.deinit(allocator);
    }
    effect_callbacks.clearAndFree(allocator);
    next_signal_id = 0;
}

/// Re-render the whole page using VDOM diffing algorithm like react
pub fn rerender() void {
    if (!is_wasm) return;
    if (Client.global_client) |client| {
        client.renderAll();
    }
}

/// Request a re-render of a specific component by ID.
pub fn scheduleRender(component_id: []const u8) void {
    if (!is_wasm) return;
    if (Client.global_client) |client| {
        for (client.components) |cmp| {
            if (std.mem.eql(u8, cmp.id, component_id)) {
                client.render(cmp) catch {};
                return;
            }
        }
    }
}

/// Cleanup function type for effects.
pub const CleanupFn = *const fn () void;

pub const EventHandler = struct {
    callback: *const fn (ctx: *anyopaque, event: zx.EventContext) void,
    context: *anyopaque,

    /// Helper to create an EventHandler from a plain function pointer (no context)
    pub fn fromFn(comptime func: *const fn (zx.EventContext) void) EventHandler {
        return .{
            .callback = &struct {
                fn wrapper(_: *anyopaque, event: zx.EventContext) void {
                    func(event);
                }
            }.wrapper,
            .context = undefined,
        };
    }
};

/// Create an effect that runs when the source signal/computed changes.
/// Like SolidJS/React, runs on mount AND on signal changes.
/// Type is inferred from the source.
///
/// ```zig
/// // Runs on mount and on every change (like SolidJS createEffect)
/// zx.effect(&count, onCountChange);
/// ```
pub fn effect(source: anytype, comptime callback: anytype) void {
    effectWithOptions(source, callback, .{ .skip_initial = false });
}

/// Create an effect that only runs when the value changes (skips initial mount).
/// Like SolidJS `createEffect(on(signal, callback, { defer: true }))`.
///
/// ```zig
/// // Skips initial mount, only runs on changes
/// zx.effectDeferred(&count, onCountChange);
/// ```
pub fn effectDeferred(source: anytype, comptime callback: anytype) void {
    effectWithOptions(source, callback, .{ .skip_initial = true });
}

const EffectOptions = struct {
    /// If true, skip the initial run on mount (only run on changes)
    skip_initial: bool = false,
};

/// Effect type (prefer `effect()` function for simpler API).
pub fn Effect(comptime T: type) type {
    return struct {
        const Self = @This();

        var auto_effects = std.ArrayList(*Self).empty;

        source_ptr: *const anyopaque,
        source_get: *const fn (*const anyopaque) T,
        source_id_ptr: *u64,
        callback: *const fn (T) ?CleanupFn,
        last_value: ?T = null,
        registered: bool = false,
        cleanup: ?CleanupFn = null,

        /// Initialize and auto-run the effect.
        /// Callback can return `void` or `?CleanupFn`.
        /// If `skip_initial` is true, skips the initial run (only fires on changes).
        pub fn init(source: anytype, comptime callback: anytype, skip_initial: bool) void {
            const SourcePtrType = @TypeOf(source);
            const source_info = @typeInfo(SourcePtrType);

            if (source_info != .pointer) {
                @compileError("Effect source must be a pointer to Signal or Computed");
            }

            const SourceType = source_info.pointer.child;

            if (!@hasDecl(SourceType, "get") or !@hasDecl(SourceType, "ensureId")) {
                @compileError("Effect source must have get() and ensureId() methods");
            }

            const CallbackType = @TypeOf(callback);
            const cb_type_info = @typeInfo(CallbackType);

            if (cb_type_info != .pointer or @typeInfo(cb_type_info.pointer.child) != .@"fn") {
                @compileError("Effect callback must be a function pointer");
            }

            const fn_info = @typeInfo(cb_type_info.pointer.child).@"fn";
            const ReturnType = fn_info.return_type orelse void;

            const wrapped_callback: *const fn (T) ?CleanupFn = comptime blk: {
                if (ReturnType == void) {
                    break :blk &struct {
                        fn wrapper(val: T) ?CleanupFn {
                            callback(val);
                            return null;
                        }
                    }.wrapper;
                } else if (ReturnType == CleanupFn) {
                    break :blk callback;
                } else {
                    @compileError("Effect callback must return void or CleanupFn");
                }
            };

            const Wrapper = struct {
                fn get(ptr: *const anyopaque) T {
                    const typed_ptr: *const SourceType = @ptrCast(@alignCast(ptr));
                    return typed_ptr.get();
                }
            };

            source.ensureId();

            const effect_ptr = allocator.create(Self) catch @panic("OOM");

            effect_ptr.* = .{
                .source_ptr = @ptrCast(source),
                .source_get = Wrapper.get,
                .source_id_ptr = &@constCast(source).id,
                .callback = wrapped_callback,
                // If skip_initial, store current value so initial run is skipped
                // If not (default), use null so effect runs on mount
                .last_value = if (skip_initial) source.get() else null,
                .registered = false,
                .cleanup = null,
            };

            auto_effects.append(allocator, effect_ptr) catch @panic("OOM");

            effect_ptr.run();
        }

        fn runWrapper(ctx: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.execute();
        }

        /// Register the effect without running it immediately.
        /// Effect will only fire when the signal value changes.
        pub fn register(self: *Self) void {
            if (!self.registered) {
                registerEffect(self.source_id_ptr.*, @ptrCast(self), runWrapper);
                self.registered = true;
            }
        }

        /// Register and run the effect immediately (React-like behavior).
        pub fn run(self: *Self) void {
            self.register();
            self.execute();
        }

        fn execute(self: *Self) void {
            const current = self.source_get(self.source_ptr);
            if (self.last_value == null or !std.meta.eql(self.last_value.?, current)) {
                if (self.cleanup) |cleanup_fn| {
                    cleanup_fn();
                }
                self.last_value = current;
                self.cleanup = self.callback(current);
            }
        }

        pub fn dispose(self: *Self) void {
            if (self.cleanup) |cleanup_fn| {
                cleanup_fn();
                self.cleanup = null;
            }
            self.registered = false;
        }
    };
}

fn effectWithOptions(source: anytype, comptime callback: anytype, options: EffectOptions) void {
    const SourcePtrType = @TypeOf(source);
    const source_info = @typeInfo(SourcePtrType);

    if (source_info != .pointer) {
        @compileError("effect source must be a pointer to a Signal or Computed");
    }

    const SourceType = source_info.pointer.child;

    if (!@hasDecl(SourceType, "ValueType")) {
        @compileError("effect source must be a Signal or Computed type");
    }

    if (!is_wasm) return;

    const T = SourceType.ValueType;
    Effect(T).init(source, callback, options.skip_initial);
}

fn ensureSignalSlot(signal_id: u64) !void {
    const idx = @as(usize, @intCast(signal_id));

    if (is_wasm) {
        if (idx >= signal_bindings.items.len) {
            try signal_bindings.ensureTotalCapacity(allocator, idx + 1);
            while (signal_bindings.items.len <= idx) {
                try signal_bindings.append(allocator, BindingList.empty);
            }
        }
    }

    if (idx >= effect_callbacks.items.len) {
        try effect_callbacks.ensureTotalCapacity(allocator, idx + 1);
        while (effect_callbacks.items.len <= idx) {
            try effect_callbacks.append(allocator, EffectList.empty);
        }
    }
}
