//! Server-side Action — context for server form action handlers.
//!
//! Provides form data parsing via `data()`.
//! For state access, use `Action.Stateful` via `ctx.bind()` or `fn(*zx.server.Action.Stateful) void`.

const std = @import("std");
const zx = @import("../../root.zig");
const Request = @import("../core/Request.zig");
const Response = @import("../core/Response.zig");
const CoreEvent = @import("../core/Event.zig");

const StateContext = CoreEvent.StateContext;
const Allocator = std.mem.Allocator;

const Action = @This();

request: Request = undefined,
response: Response = undefined,
allocator: Allocator = undefined,
arena: Allocator = undefined,
action_ref: u64 = 0,
_state_ctx: ?*StateContext = null,
/// Populated by dispatch when a stateful action sends state values in the request body.
_inputs: ?[]const []const u8 = null,

pub fn init(action_ref: u64) Action {
    return .{ .action_ref = action_ref };
}

pub fn data(self: Action, comptime T: type) T {
    comptime if (@typeInfo(T) != .@"struct") @compileError("ctx.data() requires a struct type, got: " ++ @typeName(T));

    const content_type = self.request.headers.get("content-type") orelse "";
    var result: T = undefined;

    if (std.mem.indexOf(u8, content_type, "multipart/form-data") != null) {
        const mfd = self.request.multiFormData();
        inline for (@typeInfo(T).@"struct".fields) |field| {
            if (comptime field.type == zx.File) {
                const val = mfd.get(field.name);
                @field(result, field.name) = if (val) |v| zx.File.fromBytes(v.data, v.filename orelse "", "", self.arena) else zx.File{};
            } else if (comptime field.type == ?zx.File) {
                const val = mfd.get(field.name);
                @field(result, field.name) = if (val) |v| zx.File.fromBytes(v.data, v.filename orelse "", "", self.arena) else null;
            } else {
                @field(result, field.name) = parseFormField(field.type, mfd.getValue(field.name), self.arena);
            }
        }
    } else {
        const fd = self.request.formData();
        inline for (@typeInfo(T).@"struct".fields) |field| {
            if (comptime field.type == zx.File or field.type == ?zx.File) {
                @field(result, field.name) = if (comptime field.type == zx.File) zx.File{} else null;
            } else {
                @field(result, field.name) = parseFormField(field.type, fd.get(field.name), self.arena);
            }
        }
    }

    return result;
}

/// Stateful server action — provides `state()` access to bound component state.
/// Use `fn(*zx.server.Action.Stateful) void` with `ctx.bind()` to get this type.
pub const Stateful = struct {
    _inner: *Action,
    _state_ctx: *StateContext,

    /// Access the component's state (server-side).
    /// Must be called in the same order as `ctx.state()` in the render function.
    pub fn state(self: *Stateful, comptime T: type) CoreEvent.StateHandle(T) {
        return self._state_ctx.state(T);
    }

    /// Parse form data from the action request into struct type T.
    pub fn data(self: *Stateful, comptime T: type) T {
        return self._inner.data(T);
    }

    pub fn fmt(self: Stateful, comptime format: []const u8, args: anytype) ![]u8 {
        var aw: std.Io.Writer.Allocating = .init(self._state_ctx.arena);
        defer aw.deinit();
        aw.writer.print(format, args) catch |err| switch (err) {
            error.WriteFailed => return error.OutOfMemory,
        };
        return aw.toOwnedSlice();
    }
};

fn parseFormField(comptime T: type, raw: ?[]const u8, allocator: Allocator) T {
    _ = allocator;
    switch (@typeInfo(T)) {
        .optional => |opt| return parseFormField(opt.child, raw orelse return null, undefined),
        .pointer => {
            comptime if (T != []const u8) @compileError("ctx.data(): unsupported pointer type: " ++ @typeName(T));
            return raw orelse "";
        },
        .bool => {
            const val = raw orelse return false;
            return std.mem.eql(u8, val, "true") or std.mem.eql(u8, val, "1") or std.mem.eql(u8, val, "on");
        },
        .int => return std.fmt.parseInt(T, raw orelse return 0, 10) catch 0,
        .float => return std.fmt.parseFloat(T, raw orelse return 0) catch 0,
        else => @compileError("ctx.data(): unsupported field type '" ++ @typeName(T) ++ "'"),
    }
}
