const std = @import("std");

const zx = @import("root.zig");

const reactivity = @import("runtime/client/reactivity.zig");
const Request = @import("runtime/core/Request.zig");
const Response = @import("runtime/core/Response.zig");
const CoreEvent = @import("runtime/core/Event.zig");
const ClientEvent = @import("runtime/client/Event.zig");
const ServerEvent = @import("runtime/server/Event.zig");

const StateContext = CoreEvent.StateContext;
const Allocator = std.mem.Allocator;

const platform = zx.platform;
const client_allocator = zx.client_allocator;

/// Context passed to proxy middleware functions.
pub const ProxyContext = struct {
    request: Request,
    response: Response,
    allocator: Allocator,
    arena: Allocator,

    _aborted: bool = false,
    _state_ptr: ?*const anyopaque = null,

    pub fn init(request: Request, response: Response, allocator: Allocator, arena: Allocator) ProxyContext {
        return .{ .request = request, .response = response, .allocator = allocator, .arena = arena };
    }

    pub fn state(self: *ProxyContext, value: anytype) void {
        const T = @TypeOf(value);
        const ptr = self.arena.create(T) catch return;
        ptr.* = value;
        self._state_ptr = @ptrCast(ptr);
    }

    pub fn abort(self: *ProxyContext) void {
        self._aborted = true;
    }

    pub fn next(self: *ProxyContext) void {
        _ = self;
    }

    pub fn isAborted(self: *const ProxyContext) bool {
        return self._aborted;
    }
};

/// Context for server-side form action handlers.
pub const ActionContext = struct {
    request: Request = undefined,
    response: Response = undefined,
    allocator: Allocator = undefined,
    arena: Allocator = undefined,
    action_ref: u64 = 0,
    _state_ctx: ?*StateContext = null,

    pub fn init(action_ref: u64) ActionContext {
        return .{ .action_ref = action_ref };
    }

    pub fn data(self: ActionContext, comptime T: type) T {
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

//  ----- ComponentCtx ----- //
const BindSignMsg =
    \\
    \\Handler must be one of:
    \\ - fn(*zx.client.Event.Stateful) void
    \\ - fn(*zx.client.Event) void
    \\ - fn(*zx.server.Event.Stateful) void
    \\ - fn(*zx.server.Event) void
    \\ - fn(ActionContext, *StateContext) void
    \\ - fn(struct, *StateContext) void
    \\
    \\Got:
    \\ -
;

pub fn ComponentCtx(comptime PropsType: type) type {
    return struct {
        const Self = @This();
        props: PropsType,
        allocator: Allocator,
        children: ?zx.Component = null,

        _id: u16 = 0,
        _component_id: []const u8 = "",
        _state_index: u32 = 0,
        _handler_index: u32 = 0,

        pub fn state(self: *Self, comptime T: type, initial: T) reactivity.StateInstance(T) {
            const slot = (1 << 20) + self._state_index;
            self._state_index += 1;
            return reactivity.State(T).getOrCreate(self.allocator, self._component_id, slot, initial) catch @panic("State(T).getOrCreate");
        }

        pub fn sbind(self: *Self, comptime handler: anytype, states: anytype) zx.EventHandler {
            const HandlerFnType = switch (@typeInfo(@TypeOf(handler))) {
                .@"fn" => @TypeOf(handler),
                .pointer => |p| p.child,
                else => @compileError("sbind: expected a function"),
            };
            const params = @typeInfo(HandlerFnType).@"fn".params;

            comptime if (!(params.len == 1 and params[0].type.? == *ServerEvent.Stateful))
                @compileError("sbind: handler must be fn(*zx.server.Event.Stateful) void");

            const alloc = if (platform == .browser) client_allocator else self.allocator;
            const bound_states = zx.EventHandler.buildStates(alloc, states);
            return zx.EventHandler.serverSS(handler, alloc, &self._handler_index, bound_states);
        }

        pub fn bind(self: *Self, comptime handler: anytype) zx.EventHandler {
            const alloc = if (platform == .browser) client_allocator else self.allocator;

            const HandlerType = @TypeOf(handler);
            const FnType = switch (@typeInfo(HandlerType)) {
                .@"fn" => HandlerType,
                .pointer => |p| p.child,
                else => @compileError(BindSignMsg ++ @typeName(HandlerType)),
            };
            const params = @typeInfo(FnType).@"fn".params;

            return switch (FnType) {
                // Client
                fn (*ClientEvent) void => zx.EventHandler.client(handler),
                fn (*ClientEvent.Stateful) void => zx.EventHandler.clientS(handler, alloc, self._component_id),

                // Server
                fn (*ServerEvent.Stateful) void => zx.EventHandler.serverS(handler, alloc, self._component_id, self._state_index, &self._handler_index),
                fn (*ServerEvent) void => zx.EventHandler.server(handler, alloc, &self._handler_index),

                // Server Actions
                fn (ActionContext, *StateContext) void => actionBind(handler, alloc, self),
                fn (*ActionContext) void => actionBind(handler, alloc, self),

                else => blk: {
                    if (comptime params.len == 1 and params[0].type.? == *ServerEvent) {
                        break :blk zx.EventHandler.server(handler, alloc, &self._handler_index);
                    }
                    if (comptime params.len == 2 and
                        @typeInfo(params[0].type.?) == .@"struct" and
                        params[0].type.? != ActionContext and
                        params[1].type.? == *StateContext)
                    {
                        break :blk actionBind(handler, alloc, self);
                    }
                    @compileError(BindSignMsg ++ @typeName(HandlerType));
                },
            };
        }
    };
}

fn actionBind(comptime handler: anytype, alloc: Allocator, ctx: anytype) zx.EventHandler {
    const params = @typeInfo(@TypeOf(handler)).@"fn".params;
    const arg0 = params[0].type.?;

    if (comptime params.len == 2 and params[1].type.? == *StateContext and
        (arg0 == ActionContext or @typeInfo(arg0) == .@"struct"))
    {
        const FormActionWrapper = struct {
            fn wrap(action_ctx_ptr: *ActionContext) void {
                const mfd = action_ctx_ptr.request.multiFormData();
                const states_raw = mfd.getValue("__zx_states") orelse "[]";
                const states = zx.util.zxon.parse([]const []const u8, action_ctx_ptr.arena, states_raw, .{}) catch return;
                const sc = StateContext.init(action_ctx_ptr.arena, action_ctx_ptr.arena, states) orelse return;
                action_ctx_ptr._state_ctx = sc;
                if (comptime arg0 == ActionContext) {
                    handler(action_ctx_ptr.*, sc);
                } else {
                    handler(action_ctx_ptr.data(arg0), sc);
                }
            }
        };
        return zx.EventHandler{
            .callback = &zx.EventHandler.actionHandler,
            .context = @as(*anyopaque, @ptrFromInt(1)),
            .action_fn = &FormActionWrapper.wrap,
            .bound_states = reactivity.collectStateBoundEntries(alloc, ctx._component_id, ctx._state_index),
        };
    }
}
