//! Browser Object Model (BOM) bindings for client-side JavaScript interop.
//! These types provide Zig interfaces to browser APIs like console, events, and document.
//! On server builds, these types exist but their methods are no-ops.

const std = @import("std");
const builtin = @import("builtin");

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
        // In non-WASM builds, this is a no-op - Zig will optimize away unused params
        if (!is_wasm) return;
        self.ref.call(void, "log", .{@import("js").string(data)}) catch @panic("Failed to call console.log");
    }

    pub fn @"error"(self: Console, args: anytype) void {
        if (!is_wasm) return;
        self.ref.call(void, "error", args) catch @panic("Failed to call console.error");
    }

    pub fn warn(self: Console, args: anytype) void {
        if (!is_wasm) return;
        self.ref.call(void, "warn", args) catch @panic("Failed to call console.warn");
    }

    pub fn info(self: Console, args: anytype) void {
        if (!is_wasm) return;
        self.ref.call(void, "info", args) catch @panic("Failed to call console.info");
    }

    pub fn debug(self: Console, args: anytype) void {
        if (!is_wasm) return;
        self.ref.call(void, "debug", args) catch @panic("Failed to call console.debug");
    }

    pub fn table(self: Console, args: anytype) void {
        if (!is_wasm) return;
        self.ref.call(void, "table", args) catch @panic("Failed to call console.table");
    }
};

pub const Event = struct {
    pub const EventTarget = struct {
        value: ?[]const u8 = null,
    };

    id: u64,
    ref: if (is_wasm) @import("js").Object else void,

    target: ?EventTarget = null,
    data: ?[]const u8 = null,

    pub fn idInit(allocator: std.mem.Allocator, id: u64) !Event {
        if (!is_wasm) return .{ .id = id, .ref = {}, .target = null, .data = null };
        const real_js = @import("js");
        const obj: real_js.Object = try real_js.global.get(real_js.Object, "_zx");
        const ob_val: real_js.Object = try obj.get(real_js.Object, "events");

        const current_event: real_js.Object = try ob_val.call(real_js.Object, "at", .{id});
        const target: ?real_js.Object = current_event.get(real_js.Object, "target") catch null;
        const target_value: ?[]const u8 = if (target) |t| t.getAlloc(real_js.String, allocator, "value") catch null else null;

        const event_target: ?EventTarget = if (target_value) |v| .{ .value = v } else null;
        const event_data: ?[]const u8 = current_event.getAlloc(real_js.String, allocator, "data") catch null;

        return .{
            .id = id,
            .ref = current_event,
            .target = event_target,
            .data = event_data,
        };
    }

    pub fn preventDefault(id: u64) void {
        if (!is_wasm) return;
        const real_js = @import("js");
        const obj: real_js.Object = real_js.global.get(real_js.Object, "_zx") catch @panic("Failed to get _zx");
        const ob_val: real_js.Object = obj.get(real_js.Object, "events") catch @panic("Failed to get events");
        const current_event: real_js.Object = ob_val.call(real_js.Object, "at", .{id}) catch @panic("Failed to call at");

        current_event.call(void, "preventDefault", .{}) catch @panic("Failed to call preventDefault");
    }

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

pub const Document = @import("bom/dom.zig").Document;
