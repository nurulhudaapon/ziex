const std = @import("std");
const builtin = @import("builtin");
const zx = @import("../../root.zig");
const reactivity = @import("../client/reactivity.zig");

const is_wasm = zx.platform.role == .client;
const Allocator = std.mem.Allocator;

fn getGlobalAllocator() std.mem.Allocator {
    return zx.client_allocator;
}

pub const Bound = struct {
    state_ptr: *anyopaque,
    /// Serialize the current state value to its positional JSON representation.
    getJson: *const fn (alloc: std.mem.Allocator, ptr: *anyopaque) []const u8,
    /// Apply a positional JSON value back to the local state (triggers re-render).
    applyJson: *const fn (ptr: *anyopaque, json: []const u8) void,
};

pub const Payload = struct {
    handler_id: u32 = 0,
    value: ?[]const u8 = null,
    states: []const []const u8 = &.{},
};

/// Opaque context stored per-request when bound states need round-tripping.
pub const Context = struct {
    handler_id: u32 = 0,
    bound_states: []const Bound,
    /// When false (state-only handlers), event value is omitted from the payload.
    send_event_value: bool = true,
};

callback: *const fn (ctx: *anyopaque, event: zx.client.Event) void,
context: *anyopaque,
/// Non-null when created from a form `action={}` handler.
/// Takes a pointer so the server wrapper can write `_state_ctx` back after the call.
action_fn: ?*const fn (*zx.server.Action) void = null,
/// Server-side handler; takes *ServerEventContext so the wrapper can set _state_ctx.
server_event_fn: ?*const fn (*zx.server.Event) void = null,
/// Unique ID for this handler instance on the current page.
handler_id: u32 = 0,
/// States to serialize/deserialize for server event round-trips.
bound_states: []const Bound = &.{},
/// True when the handler may reach suspending browser imports and must be
/// invoked through the async/JSPI event path.
may_suspend: bool = false,

const Self = @This();

/// Helper to create an EventHandler from a plain function pointer (no context).
pub fn wrap(comptime func: anytype) Self {
    const FnType = @TypeOf(func);
    const fn_info = @typeInfo(FnType);
    const params = fn_info.@"fn".params;

    // Server action: fn (zx.server.Action) void
    if (comptime params.len == 1) {
        const arg_type = params[0].type.?;
        switch (arg_type) {
            zx.server.Action => {
                const Wrap = struct {
                    fn w(ctx: *zx.server.Action) void {
                        func(ctx.*);
                    }
                };
                return .{
                    .callback = &actionHandler,
                    .context = @as(*anyopaque, @ptrFromInt(1)),
                    .action_fn = &Wrap.w,
                };
            },
            zx.server.Event => {
                const Wrapper = struct {
                    fn w(ctx: *zx.server.Event) void {
                        func(ctx.*);
                    }
                };
                return .{
                    .callback = &eventHandler,
                    .context = @as(*anyopaque, @ptrFromInt(1)),
                    .server_event_fn = &Wrapper.w,
                };
            },
            *zx.server.Event.Stateful => {
                @compileError(
                    "fn(*zx.server.Event.Stateful) void handlers require ctx.bind(). " ++
                        "Use fn(zx.server.Event) void for non-bind server event handlers.",
                );
            },
            else => {
                if (comptime @typeInfo(arg_type) == .@"struct" and arg_type != zx.client.Event) {
                    @compileError(
                        "A struct-typed handler `" ++ @typeName(@TypeOf(func)) ++ "` can only be used " ++
                            "as a form `action={}` attribute, not as an event handler.",
                    );
                }
            },
        }
    }

    const Wrapper = struct {
        fn wrapper(ctx: *anyopaque, event: zx.client.Event) void {
            _ = ctx;
            if (comptime params.len == 0) {
                func();
            } else {
                func(event);
            }
        }
    };
    return .{
        .callback = &Wrapper.wrapper,
        .context = @as(*anyopaque, @ptrFromInt(1)),
        .may_suspend = true,
    };
}

/// Helper to create an EventHandler from a form `action={}` attribute.
pub fn action(comptime func: anytype) Self {
    const FnType = @TypeOf(func);
    const fn_info = @typeInfo(FnType);
    const params = fn_info.@"fn".params;

    if (comptime params.len == 1) {
        const arg_type = params[0].type.?;
        if (comptime @typeInfo(arg_type) == .@"struct" and
            arg_type != zx.server.Action and
            arg_type != zx.client.Event and
            arg_type != zx.server.Event)
        {
            const DirectTyped = struct {
                fn w(ctx: *zx.server.Action) void {
                    func(ctx.data(arg_type));
                }
            };
    return .{
        .callback = &actionHandler,
        .context = @as(*anyopaque, @ptrFromInt(1)),
        .action_fn = &DirectTyped.w,
        .may_suspend = false,
    };
        }
    }
    return wrap(func);
}

/// Helper to create an EventHandler from a runtime function pointer (no context)
pub fn runtime(func: *const fn (zx.client.Event) void) Self {
    return .{
        .callback = &struct {
            fn w(ctx: *anyopaque, event: zx.client.Event) void {
                const f: *const fn (zx.client.Event) void = @ptrCast(@alignCast(ctx));
                f(event);
            }
        }.w,
        .context = @ptrCast(@constCast(func)),
        .may_suspend = true,
    };
}

/// Helper to create an EventHandler from a runtime function pointer with pointer receiver
pub fn runtimePtr(func: *const fn (*zx.client.Event) void) Self {
    return .{
        .callback = &struct {
            fn w(ctx: *anyopaque, event: zx.client.Event) void {
                const f: *const fn (*zx.client.Event) void = @ptrCast(@alignCast(ctx));
                var e = event;
                f(&e);
            }
        }.w,
        .context = @ptrCast(@constCast(func)),
        .may_suspend = true,
    };
}

/// Stateless client handler: fn(*zx.client.Event) void
pub fn client(comptime handler: anytype) Self {
    const Wrap = struct {
        fn w(_: *anyopaque, event: zx.client.Event) void {
            var e = event;
            handler(&e);
        }
    };
    return .{
        .callback = &Wrap.w,
        .context = @as(*anyopaque, @ptrFromInt(1)),
        .may_suspend = true,
    };
}

/// Stateful client handler: fn(*zx.client.Event.Stateful) void
pub fn clientS(comptime handler: anytype, alloc: Allocator, component_id: []const u8) Self {
    const cid = alloc.create([]const u8) catch @panic("OOM");
    cid.* = alloc.dupe(u8, component_id) catch @panic("OOM");
    const Wrap = struct {
        fn w(ctx: *anyopaque, event: zx.client.Event) void {
            const p: *[]const u8 = @ptrCast(@alignCast(ctx));
            var e = event;
            var sf = zx.client.Event.Stateful{ ._inner = &e, ._component_id = p.* };
            handler(&sf);
        }
    };
    return .{
        .callback = &Wrap.w,
        .context = @ptrCast(cid),
        .may_suspend = true,
    };
}

/// Stateless server handler: fn(*zx.server.Event) void
pub fn server(comptime handler: anytype, alloc: Allocator, handler_index: *u32) Self {
    const Wrap = struct {
        fn wrap(ctx: *zx.server.Event) void {
            handler(ctx);
        }
    };
    return finalizeServer(alloc, handler_index, &Wrap.wrap, &.{});
}

/// Stateful server handler: fn(*zx.server.Event.Stateful) void (auto-binds states)
pub fn serverS(
    comptime handler: anytype,
    alloc: Allocator,
    component_id: []const u8,
    state_index: u32,
    handler_index: *u32,
) Self {
    const wrap_fn = makeServerWrap(handler, struct {
        fn call(ctx: *zx.server.Event, sc: *zx.StateContext, h: anytype) void {
            var sf = zx.server.Event.Stateful{ ._inner = ctx, ._state_ctx = sc };
            h(&sf);
        }
    }.call);
    return finalizeServer(alloc, handler_index, &wrap_fn, reactivity.collectStateBoundEntries(alloc, component_id, state_index));
}

/// Stateful server handler with explicitly listed states (user-provided)
pub fn serverSS(
    comptime handler: anytype,
    alloc: Allocator,
    handler_index: *u32,
    bound_states: []const Bound,
) Self {
    const wrap_fn = makeServerWrap(handler, struct {
        fn call(ctx: *zx.server.Event, sc: *zx.StateContext, h: anytype) void {
            var sf = zx.server.Event.Stateful{ ._inner = ctx, ._state_ctx = sc };
            h(&sf);
        }
    }.call);
    return finalizeServer(alloc, handler_index, &wrap_fn, bound_states);
}

/// Stateful action handler: fn(*zx.server.Action.Stateful) void (auto-binds states from component)
pub fn actionStateful(
    comptime handler: anytype,
    alloc: Allocator,
    component_id: []const u8,
    state_index: u32,
    handler_index: *u32,
) Self {
    const ActionWrap = struct {
        fn wrap(ctx: *zx.server.Action) void {
            const sc = zx.StateContext.init(ctx.allocator, ctx.arena, ctx._inputs orelse &.{}) orelse return;
            ctx._state_ctx = sc;
            var sf = zx.server.Action.Stateful{ ._inner = ctx, ._state_ctx = sc };
            handler(&sf);
        }
    };
    const bound = reactivity.collectStateBoundEntries(alloc, component_id, state_index);
    handler_index.* += 1;
    const h_id = handler_index.*;
    const ec = alloc.create(Context) catch @panic("OOM");
    ec.* = .{ .handler_id = h_id, .bound_states = bound };
    return .{
        .callback = &actionHandler,
        .context = @ptrCast(ec),
        .action_fn = &ActionWrap.wrap,
        .handler_id = h_id,
        .bound_states = bound,
    };
}

/// Build Bound vtable for explicitly listed states.
pub fn buildStates(alloc: Allocator, states: anytype) []const Bound {
    const state_fields = @typeInfo(@TypeOf(states)).@"struct".fields;
    const arr = alloc.alloc(Bound, state_fields.len) catch @panic("OOM");
    inline for (state_fields, 0..) |field, i| {
        const s = @field(states, field.name);
        const T = @typeInfo(@TypeOf(s)).pointer.child.ValueType;
        arr[i] = .{
            .state_ptr = @ptrCast(s),
            .getJson = &struct {
                fn f(a: Allocator, ptr: *anyopaque) []const u8 {
                    const st: *reactivity.State(T) = @ptrCast(@alignCast(ptr));
                    var aw = std.Io.Writer.Allocating.init(a);
                    zx.util.zxon.serialize(st.get(), &aw.writer, .{}) catch return "null";
                    return aw.written();
                }
            }.f,
            .applyJson = &struct {
                fn f(ptr: *anyopaque, json: []const u8) void {
                    const st: *reactivity.State(T) = @ptrCast(@alignCast(ptr));
                    st.set(zx.util.zxon.parse(T, getGlobalAllocator(), json, .{}) catch return);
                }
            }.f,
        };
    }
    return arr;
}

/// Minimal server action handler (POSTs to current page).
pub fn actionS() Self {
    return .{
        .callback = &actionHandler,
        .context = @as(*anyopaque, @ptrFromInt(1)),
    };
}

fn makeServerWrap(
    comptime handler: anytype,
    comptime call: fn (*zx.server.Event, *zx.StateContext, anytype) void,
) fn (*zx.server.Event) void {
    return struct {
        fn wrap(ctx: *zx.server.Event) void {
            const sc = zx.StateContext.init(ctx.allocator, ctx.arena, ctx.payload.states) orelse return;
            ctx._state_ctx = sc;
            call(ctx, sc, handler);
        }
    }.wrap;
}

fn finalizeServer(
    alloc: Allocator,
    handler_index: *u32,
    comptime wrap_fn: *const fn (*zx.server.Event) void,
    bound_states: []const Bound,
) Self {
    handler_index.* += 1;
    const h_id = handler_index.*;
    const ctx = alloc.create(Context) catch @panic("OOM");
    ctx.* = .{ .handler_id = h_id, .bound_states = bound_states };
    return init(h_id, wrap_fn, @ptrCast(ctx), bound_states);
}

pub fn init(
    handler_id: u32,
    comptime server_fn: *const fn (*zx.server.Event) void,
    context: *anyopaque,
    bound_states: []const Bound,
) Self {
    return .{
        .handler_id = handler_id,
        .callback = &eventHandler,
        .context = context,
        .server_event_fn = server_fn,
        .bound_states = bound_states,
    };
}

pub fn actionHandler(ctx: *anyopaque, event: zx.client.Event) void {
    if (!is_wasm) return;
    event.preventDefault();
    const client_fetch = @import("../client/fetch.zig");
    const CoreFetch = @import("Fetch.zig");

    const bound_states: []const Bound = if (@intFromPtr(ctx) == 1)
        &.{}
    else blk: {
        const ec: *Context = @ptrCast(@alignCast(ctx));
        break :blk ec.bound_states;
    };

    const headers = [_]CoreFetch.RequestInit.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "X-ZX-Action", .value = "1" },
    };

    if (bound_states.len > 0) {
        var state_jsons = std.ArrayList([]const u8).empty;
        for (bound_states) |bs| {
            const json = bs.getJson(getGlobalAllocator(), bs.state_ptr);
            state_jsons.append(getGlobalAllocator(), json) catch {};
        }

        var aw = std.Io.Writer.Allocating.init(getGlobalAllocator());
        zx.util.zxon.serialize(state_jsons.items, &aw.writer, .{}) catch {};
        const payload_buf = aw.written();

        const cb_ctx = getGlobalAllocator().create(Context) catch return;
        cb_ctx.* = .{ .bound_states = bound_states };
        client_fetch.fetchAsyncCtx(
            getGlobalAllocator(),
            "",
            .{ .method = .POST, .headers = &headers, .body = payload_buf },
            @ptrCast(cb_ctx),
            onEventResponse,
        );
    } else {
        client_fetch.fetchAsync(
            getGlobalAllocator(),
            "",
            .{
                .method = .GET,
                .headers = &headers,
                .body = "{}",
            },
            onActionResponse,
        );
    }
}

fn eventHandler(ctx: *anyopaque, event: zx.client.Event) void {
    if (!is_wasm) return;
    event.preventDefault();

    const client_fetch = @import("../client/fetch.zig");
    const CoreFetch = @import("Fetch.zig");

    var handler_id: u32 = 0;
    const bound_states: []const Bound = if (@intFromPtr(ctx) == 1)
        &.{}
    else blk: {
        const ec: *Context = @ptrCast(@alignCast(ctx));
        handler_id = ec.handler_id;
        break :blk ec.bound_states;
    };

    const send_event_value: bool = if (@intFromPtr(ctx) == 1) true else blk: {
        const ec: *Context = @ptrCast(@alignCast(ctx));
        break :blk ec.send_event_value;
    };

    var state_jsons = std.ArrayList([]const u8).empty;
    for (bound_states) |bs| {
        const json = bs.getJson(getGlobalAllocator(), bs.state_ptr);
        state_jsons.append(getGlobalAllocator(), json) catch {};
    }

    const headers = [_]CoreFetch.RequestInit.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "X-ZX-Server-Event", .value = "1" },
    };

    const payload = Payload{
        .handler_id = handler_id,
        .value = if (send_event_value) event.value() else null,
        .states = state_jsons.items,
    };

    var aw = std.Io.Writer.Allocating.init(getGlobalAllocator());
    zx.util.zxon.serialize(payload, &aw.writer, .{}) catch {};
    const payload_buf = aw.written();

    if (bound_states.len > 0) {
        const cb_ctx = getGlobalAllocator().create(Context) catch return;
        cb_ctx.* = .{ .bound_states = bound_states };
        client_fetch.fetchAsyncCtx(
            getGlobalAllocator(),
            "",
            .{ .method = .POST, .headers = &headers, .body = payload_buf },
            @ptrCast(cb_ctx),
            onEventResponse,
        );
    } else {
        client_fetch.fetchAsync(
            getGlobalAllocator(),
            "",
            .{ .method = .POST, .headers = &headers, .body = payload_buf },
            onActionResponse,
        );
    }
}

fn onActionResponse(_: ?*@import("Fetch.zig").Response, _: ?@import("Fetch.zig").FetchError) void {}

fn onEventResponse(ctx_ptr: *anyopaque, response: ?*@import("Fetch.zig").Response, _: ?@import("Fetch.zig").FetchError) void {
    const cb_ctx: *Context = @ptrCast(@alignCast(ctx_ptr));
    defer getGlobalAllocator().destroy(cb_ctx);

    const resp = response orelse return;
    const body = resp._body;
    if (body.len == 0) return;

    const states = zx.util.zxon.parse([]const []const u8, getGlobalAllocator(), body, .{}) catch return;
    for (states, 0..) |state_json, i| {
        if (i >= cb_ctx.bound_states.len) break;
        cb_ctx.bound_states[i].applyJson(cb_ctx.bound_states[i].state_ptr, state_json);
    }
}
