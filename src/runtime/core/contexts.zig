const zx = @import("../../root.zig");
const reactivity = @import("../client/reactivity.zig");

const ActionContext = @import("../server/Action.zig");
const ClientEvent = @import("../client/Event.zig");
const CoreEvent = @import("Event.zig");
const Request = @import("Request.zig");
const Response = @import("Response.zig");
const ServerEvent = @import("../server/Event.zig");

const StateContext = CoreEvent.StateContext;
const Allocator = zx.Allocator;

// TODO: Re-work proxy arhitecture to allow intercepting request before and after
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

//  ----- ComponentCtx ----- //
const BindSignMsg =
    \\
    \\Handler must be one of:
    \\ - fn(*zx.client.Event.Stateful) void
    \\ - fn(*zx.client.Event) void
    \\ - fn(*zx.server.Event.Stateful) void
    \\ - fn(*zx.server.Event) void
    \\ - fn(*zx.server.Action.Stateful) void
    \\ - fn(*zx.server.Action) void
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

        _internal: Internal = .{},

        pub const Internal = struct {
            component_id: []const u8 = "",
            state_idx: u32 = 0,
        };

        pub fn state(self: *Self, comptime T: type, initial: T) reactivity.StateInstance(T) {
            const slot = (1 << 20) + self._internal.state_idx;
            self._internal.state_idx += 1;
            return reactivity.State(T).getOrCreate(self.allocator, self._internal.component_id, slot, initial) catch @panic("State(T).getOrCreate");
        }

        pub fn sbind(self: *Self, comptime handler: anytype, states: anytype) zx.EventHandler {
            const HandlerFnType = switch (@typeInfo(@TypeOf(handler))) {
                .@"fn" => @TypeOf(handler),
                .pointer => |p| p.child,
                else => @compileError("sbind: expected a function"),
            };
            const params = @typeInfo(HandlerFnType).@"fn".param_types;

            comptime if (!(params.len == 1 and params[0].? == *ServerEvent.Stateful))
                @compileError("sbind: handler must be fn(*zx.server.Event.Stateful) void");

            const alloc = if (zx.platform.role == .client) zx.allocator else self.allocator;
            const bound_states = zx.EventHandler.buildStates(alloc, states);
            return zx.EventHandler.serverSS(handler, alloc, bound_states);
        }

        pub fn bind(self: *Self, comptime handler: anytype) zx.EventHandler {
            const alloc = if (zx.platform.role == .client) zx.allocator else self.allocator;

            const HandlerType = @TypeOf(handler);
            const FnType = switch (@typeInfo(HandlerType)) {
                .@"fn" => HandlerType,
                .pointer => |p| p.child,
                else => @compileError(BindSignMsg ++ @typeName(HandlerType)),
            };
            const params = @typeInfo(FnType).@"fn".param_types;

            return switch (FnType) {
                // Client
                fn (*ClientEvent) void => zx.EventHandler.client(handler),
                fn (*ClientEvent.Stateful) void => zx.EventHandler.clientS(handler, alloc, self._internal.component_id),

                // Server
                fn (*ServerEvent.Stateful) void => zx.EventHandler.serverS(handler, alloc, self._internal.component_id, self._internal.state_idx),
                fn (*ServerEvent) void => zx.EventHandler.server(handler, alloc),

                // Server Actions
                fn (*ActionContext.Stateful) void => zx.EventHandler.actionStateful(handler, alloc, self._internal.component_id, self._internal.state_idx),
                fn (ActionContext, *StateContext) void => actionBind(handler, alloc, self),
                fn (*ActionContext) void => actionBind(handler, alloc, self),

                else => blk: {
                    if (comptime params.len == 1 and params[0] == *ServerEvent) {
                        break :blk zx.EventHandler.server(handler, alloc);
                    }
                    if (comptime params.len == 2 and
                        @typeInfo(params[0].?) == .@"struct" and
                        params[0] != ActionContext and
                        params[1] == *StateContext)
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
    const params = @typeInfo(@TypeOf(handler)).@"fn".param_types;
    const arg0 = params[0].?;

    if (comptime params.len == 2 and params[1] == *StateContext and
        (arg0 == ActionContext or @typeInfo(arg0) == .@"struct"))
    {
        const FormActionWrapper = struct {
            fn wrap(action_ctx_ptr: *ActionContext) void {
                const inputs = action_ctx_ptr._internal.inputs orelse &.{};
                const sc = StateContext.init(action_ctx_ptr.arena, action_ctx_ptr.arena, inputs) orelse return;
                action_ctx_ptr._internal.state_ctx = sc;
                if (comptime arg0 == ActionContext) {
                    handler(action_ctx_ptr.*, sc);
                } else {
                    handler(action_ctx_ptr.data(arg0), sc);
                }
            }
        };
        const bound = reactivity.collectStateBoundEntries(alloc, ctx._internal.component_id, ctx._internal.state_idx);
        const ec = alloc.create(zx.EventHandler.Context) catch @panic("OOM");
        // handler_id is stamped later in `x.Context.attr` from the attribute @src().
        ec.* = .{ .handler_id = 0, .bound_states = bound };
        return zx.EventHandler{
            .callback = &zx.EventHandler.actionHandler,
            .context = @ptrCast(ec),
            .action_fn = &FormActionWrapper.wrap,
            .bound_states = bound,
        };
    }
}
