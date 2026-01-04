//! Reactive Signal primitive for client-side state management.
//! Signals provide fine-grained reactivity - when a signal's value changes,
//! only the DOM nodes that depend on it are updated (no full re-render).
//!
//! This follows SolidJS's approach: no tree walking or diffing.
//! Each signal maintains direct references to its bound DOM text nodes.
//! When set() is called, only those specific nodes are updated.
//!
//! Usage:
//! ```zig
//! var count = Signal(i32).init(0);
//!
//! // In template: {count} - automatically creates reactive binding
//! // When count.set(5) is called, the DOM text node updates directly
//! ```

const std = @import("std");
const builtin = @import("builtin");

/// Whether we're running in a browser environment (WASM)
const is_wasm = builtin.cpu.arch == .wasm32 or builtin.cpu.arch == .wasm64;

/// JS bindings - only available in WASM builds
const js = if (is_wasm) @import("js") else struct {
    pub const Object = void;
    pub fn string(_: []const u8) void {}
};

/// Global signal ID counter for unique identification
var next_signal_id: u64 = 0;

/// Global client reference for triggering re-renders
var global_client: ?*@import("Client.zig") = null;

/// Registry of signal_id → text node references for direct DOM updates.
/// This is the key to SolidJS-like fine-grained reactivity: no tree walking,
/// just direct reference lookups.
const SignalBinding = struct {
    text_node: JsObject,
};

/// JS Object type - real in WASM, void stub on server
const JsObject = if (is_wasm) @import("js").Object else void;

/// Maximum number of bindings per signal (for static allocation)
const MAX_BINDINGS_PER_SIGNAL: usize = 16;
/// Maximum number of signals we can track
const MAX_SIGNALS: usize = 256;

/// Signal bindings registry: signal_id → array of text node refs
/// Only used in WASM builds for DOM binding
var signal_bindings: if (is_wasm) [MAX_SIGNALS][MAX_BINDINGS_PER_SIGNAL]?JsObject else void =
    if (is_wasm) .{.{null} ** MAX_BINDINGS_PER_SIGNAL} ** MAX_SIGNALS else {};
var binding_counts: [MAX_SIGNALS]usize = .{0} ** MAX_SIGNALS;

/// Register a text node binding for a signal
/// No-op on server builds
pub fn registerBinding(signal_id: u64, text_node: JsObject) void {
    if (!is_wasm) return;
    if (signal_id >= MAX_SIGNALS) return;
    const idx = @as(usize, @intCast(signal_id));
    const count = binding_counts[idx];

    if (count < MAX_BINDINGS_PER_SIGNAL) {
        signal_bindings[idx][count] = text_node;
        binding_counts[idx] = count + 1;
    }
}

/// Clear all bindings for a signal (call when re-rendering)
/// No-op on server builds
pub fn clearBindings(signal_id: u64) void {
    if (!is_wasm) return;
    if (signal_id >= MAX_SIGNALS) return;
    const idx = @as(usize, @intCast(signal_id));
    // Deinit old references
    for (0..binding_counts[idx]) |i| {
        if (signal_bindings[idx][i]) |node| {
            node.deinit();
        }
        signal_bindings[idx][i] = null;
    }
    binding_counts[idx] = 0;
}

/// Effect callback type: type-erased function pointer
const EffectCallback = struct {
    context: *anyopaque,
    run_fn: *const fn (*anyopaque) void,
};

/// Maximum effects per signal
const MAX_EFFECTS_PER_SIGNAL: usize = 8;

/// Effect registry: signal_id → array of effect callbacks
var effect_callbacks: [MAX_SIGNALS][MAX_EFFECTS_PER_SIGNAL]?EffectCallback = .{.{null} ** MAX_EFFECTS_PER_SIGNAL} ** MAX_SIGNALS;
var effect_counts: [MAX_SIGNALS]usize = .{0} ** MAX_SIGNALS;

/// Register an effect callback for a signal
pub fn registerEffect(signal_id: u64, context: *anyopaque, run_fn: *const fn (*anyopaque) void) void {
    if (signal_id >= MAX_SIGNALS) return;
    const idx = @as(usize, @intCast(signal_id));
    const count = effect_counts[idx];
    if (count < MAX_EFFECTS_PER_SIGNAL) {
        effect_callbacks[idx][count] = .{ .context = context, .run_fn = run_fn };
        effect_counts[idx] = count + 1;
    }
}

/// Run all effects for a signal
fn runEffects(signal_id: u64) void {
    if (signal_id >= MAX_SIGNALS) return;
    const idx = @as(usize, @intCast(signal_id));
    const count = effect_counts[idx];
    for (0..count) |i| {
        if (effect_callbacks[idx][i]) |cb| {
            cb.run_fn(cb.context);
        }
    }
}

/// Set the global client reference (called during client initialization)
pub fn setGlobalClient(client: *@import("Client.zig")) void {
    global_client = client;
}

/// Get the global client reference
pub fn getGlobalClient() ?*@import("Client.zig") {
    return global_client;
}

/// Request a full re-render of all components.
/// Useful when state is modified outside of event handlers.
pub fn requestRender() void {
    if (global_client) |client| {
        client.renderAll();
    }
}

/// Request a re-render of a specific component by ID.
pub fn scheduleRender(component_id: []const u8) void {
    if (global_client) |client| {
        for (client.components) |cmp| {
            if (std.mem.eql(u8, cmp.id, component_id)) {
                client.render(cmp) catch {};
                return;
            }
        }
    }
}

/// Reactive Signal type for fine-grained client-side state management.
/// Each signal has a unique ID that's used to track DOM bindings.
/// When set() is called, the signal directly updates its bound DOM nodes.
pub fn Signal(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Unique identifier for this signal instance (comptime-known from call site)
        id: u64,
        /// The current value
        value: T,
        /// Whether runtime ID has been assigned
        runtime_id_assigned: bool = false,

        /// Initialize a signal with an initial value.
        /// Uses comptime source location hash for unique ID.
        pub fn init(initial: T) Self {
            return initWithId(initial, 0);
        }

        /// Initialize with a specific ID (for runtime assignment)
        pub fn initWithId(initial: T, id: u64) Self {
            return .{ .id = id, .value = initial, .runtime_id_assigned = id != 0 };
        }

        /// Ensure this signal has a runtime ID assigned.
        /// Uses @constCast because signals are always module-level vars.
        pub fn ensureId(self: anytype) void {
            const mutable = @constCast(self);
            if (!mutable.runtime_id_assigned) {
                mutable.id = next_signal_id;
                next_signal_id += 1;
                mutable.runtime_id_assigned = true;
            }
        }

        /// Get the current value (read-only).
        pub inline fn get(self: *const Self) T {
            return self.value;
        }

        /// Get a mutable pointer to the value.
        /// Note: Direct mutation won't trigger DOM updates.
        /// Call set() or notifyChange() after modification.
        pub inline fn ptr(self: *Self) *T {
            return &self.value;
        }

        /// Set a new value and update all bound DOM nodes.
        pub fn set(self: *Self, new_value: T) void {
            self.value = new_value;
            self.notifyChange();
        }

        /// Update the value using a function and update bound DOM nodes.
        pub fn update(self: *Self, comptime updater: fn (T) T) void {
            self.value = updater(self.value);
            self.notifyChange();
        }

        /// Notify the DOM and effects that this signal's value has changed.
        /// Updates all bound text nodes and runs all registered effects.
        pub fn notifyChange(self: *const Self) void {
            updateSignalNodes(self.id, self.value);
            runEffects(self.id);
        }

        /// Check if the signal's value equals another value.
        pub inline fn eql(self: *const Self, other: T) bool {
            return std.meta.eql(self.value, other);
        }

        /// Format the value as a string (used internally for DOM updates)
        pub fn format(self: *const Self, buf: []u8) []const u8 {
            return formatValue(T, self.value, buf);
        }
    };
}

/// Format any value to a string for DOM text content
fn formatValue(comptime T: type, value: T, buf: []u8) []const u8 {
    return switch (@typeInfo(T)) {
        .int, .comptime_int => std.fmt.bufPrint(buf, "{d}", .{value}) catch "?",
        .float, .comptime_float => std.fmt.bufPrint(buf, "{d:.2}", .{value}) catch "?",
        .bool => if (value) "true" else "false",
        .pointer => |ptr_info| blk: {
            if (ptr_info.size == .slice and ptr_info.child == u8) {
                break :blk value; // Already a string
            }
            break :blk std.fmt.bufPrint(buf, "{any}", .{value}) catch "?";
        },
        .@"enum" => @tagName(value),
        .optional => if (value) |v| formatValue(@TypeOf(v), v, buf) else "",
        else => std.fmt.bufPrint(buf, "{any}", .{value}) catch "?",
    };
}

/// Update all DOM text nodes bound to a signal.
/// Uses direct registry lookups - no DOM querying or tree walking (SolidJS-style).
/// No-op on server builds (no DOM to update).
fn updateSignalNodes(signal_id: u64, value: anytype) void {
    // On server builds, there's no DOM to update
    if (!is_wasm) return;
    if (signal_id >= MAX_SIGNALS) return;

    const T = @TypeOf(value);
    const idx = @as(usize, @intCast(signal_id));
    const count = binding_counts[idx];

    if (count == 0) return;

    // Format the value to a string
    var buf: [256]u8 = undefined;
    const text = formatValue(T, value, &buf);

    // Update each bound text node directly - no tree walking!
    for (0..count) |i| {
        if (signal_bindings[idx][i]) |node| {
            // Text nodes use nodeValue, not textContent
            node.set("nodeValue", @import("js").string(text)) catch {};
        }
    }
}

/// Check if a type is a Signal type (used at comptime)
pub fn isSignalType(comptime T: type) bool {
    const info = @typeInfo(T);

    // Check if it's a pointer to a Signal-like struct
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

/// Get the value type from a Signal pointer type
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

/// Create a derived/computed value that depends on a signal.
/// Computed values are reactive - they automatically update their DOM bindings
/// when the source signal changes. Internally acts like a Signal.
pub fn Computed(comptime T: type, comptime SourceT: type) type {
    return struct {
        const Self = @This();

        /// Unique ID for DOM binding (like Signal)
        id: u64 = 0,
        /// Whether runtime ID has been assigned
        runtime_id_assigned: bool = false,
        /// Cached computed value (initialized on first get/subscribe)
        value: T = undefined,
        /// Whether value has been computed at least once
        initialized: bool = false,
        /// Source signal to derive from
        source: *const Signal(SourceT),
        /// Computation function
        compute: *const fn (SourceT) T,
        /// Whether subscribed to source
        subscribed: bool = false,

        pub fn init(source: *const Signal(SourceT), compute: *const fn (SourceT) T) Self {
            // Don't compute initial value at comptime - defer to runtime
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

        /// Ensure this computed has a runtime ID assigned
        pub fn ensureId(self: anytype) void {
            const mutable = @constCast(self);
            if (!mutable.runtime_id_assigned) {
                mutable.id = next_signal_id;
                next_signal_id += 1;
                mutable.runtime_id_assigned = true;
            }
        }

        /// Ensure value is computed (call at runtime before first use)
        fn ensureInitialized(self: anytype) void {
            const mutable = @constCast(self);
            if (!mutable.initialized) {
                mutable.value = mutable.compute(mutable.source.get());
                mutable.initialized = true;
            }
        }

        /// Subscribe to source signal changes
        pub fn subscribe(self: *Self) void {
            if (self.subscribed) return;
            self.ensureInitialized();
            self.source.ensureId();
            registerEffect(self.source.id, @ptrCast(self), updateWrapper);
            self.subscribed = true;
        }

        /// Type-erased wrapper for effect registry
        fn updateWrapper(ctx: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.recompute();
        }

        /// Recompute the value and update DOM bindings
        fn recompute(self: *Self) void {
            const new_value = self.compute(self.source.get());
            self.value = new_value;
            // Update DOM bindings for this computed's ID
            updateSignalNodes(self.id, new_value);
        }

        /// Get the current computed value (computes on first call)
        pub fn get(self: anytype) T {
            const mutable = @constCast(self);
            mutable.ensureInitialized();
            return mutable.value;
        }

        /// Notify DOM that this computed's value changed (for manual triggers)
        pub fn notifyChange(self: *const Self) void {
            updateSignalNodes(self.id, self.value);
        }
    };
}

/// Effect that runs when its source signal changes.
/// Automatically subscribes to the signal on first run.
/// SolidJS-style: effects are triggered by signal.set() calls.
pub fn Effect(comptime T: type) type {
    return struct {
        const Self = @This();

        source: *const Signal(T),
        callback: *const fn (T) void,
        last_value: ?T = null,
        registered: bool = false,

        pub fn init(source: *const Signal(T), callback: *const fn (T) void) Self {
            return .{
                .source = source,
                .callback = callback,
                .last_value = null,
                .registered = false,
            };
        }

        /// Type-erased wrapper for the registry
        fn runWrapper(ctx: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.execute();
        }

        /// Run the effect: register with signal and execute immediately.
        /// After first run, the effect will be called automatically on signal changes.
        pub fn run(self: *Self) void {
            // Register with the signal's effect registry (only once)
            if (!self.registered) {
                self.source.ensureId();
                registerEffect(self.source.id, @ptrCast(self), runWrapper);
                self.registered = true;
            }
            // Execute immediately on first run
            self.execute();
        }

        /// Execute the effect if the value has changed.
        fn execute(self: *Self) void {
            const current = self.source.get();
            if (self.last_value == null or !std.meta.eql(self.last_value.?, current)) {
                self.last_value = current;
                self.callback(current);
            }
        }
    };
}
