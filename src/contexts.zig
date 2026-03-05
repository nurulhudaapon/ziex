const std = @import("std");
const builtin = @import("builtin");

const Request = @import("runtime/core/Request.zig");
const Response = @import("runtime/core/Response.zig");
const pltfm = @import("platform.zig");
const platform = pltfm.platform;
const client = @import("runtime/client/window.zig");

const Allocator = std.mem.Allocator;

const client_allocator = if (builtin.os.tag == .freestanding) std.heap.wasm_allocator else std.heap.page_allocator;

/// Context passed to proxy middleware functions.
/// Use `state.set()` to pass typed data to downstream route/page handlers.
pub const ProxyContext = struct {
    request: Request,
    response: Response,
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,

    //TODO: move these to single _inner ptr
    _aborted: bool = false,
    _state_ptr: ?*const anyopaque = null,

    pub fn init(request: Request, response: Response, allocator: std.mem.Allocator, arena: std.mem.Allocator) ProxyContext {
        return .{
            .request = request,
            .response = response,
            .allocator = allocator,
            .arena = arena,
        };
    }

    /// Set typed state data to be passed to downstream route/page handlers.
    /// (e.g., `zx.RouteCtx(AppCtx, MyState)` or `zx.PageCtx(AppCtx, MyState)`).
    pub fn state(self: *ProxyContext, value: anytype) void {
        const T = @TypeOf(value);
        const ptr = self.arena.create(T) catch return;
        ptr.* = value;
        self._state_ptr = @ptrCast(ptr);
    }

    /// Abort the request chain - no further handlers (proxies, page, route) will be called
    /// Use this when the proxy has fully handled the request (e.g., returned an error response)
    pub fn abort(self: *ProxyContext) void {
        self._aborted = true;
    }

    /// Continue to the next handler in the chain
    /// This is a no-op (chain continues by default), but makes intent explicit
    pub fn next(self: *ProxyContext) void {
        _ = self;
        // No-op - chain continues by default unless abort() is called
    }

    /// Check if the request chain was aborted
    pub fn isAborted(self: *const ProxyContext) bool {
        return self._aborted;
    }
};

pub const EventContext = struct {
    /// The JS event object reference (as a u64 NaN-boxed value)
    event_ref: u64,

    pub fn init(event_ref: u64) EventContext {
        return .{ .event_ref = event_ref };
    }

    /// Get the underlying js.Object for the event
    pub fn getEvent(self: EventContext) client.Event {
        return client.Event.fromRef(self.event_ref);
    }

    /// Get the underlying js.Object with data loaded (value, key, etc)
    pub fn getEventWithData(self: EventContext, allocator: std.mem.Allocator) client.Event {
        return client.Event.fromRefWithData(allocator, self.event_ref);
    }

    pub fn preventDefault(self: EventContext) void {
        self.getEvent().preventDefault();
    }

    /// Get the input value from event.target.value
    pub fn value(self: EventContext) ?[]const u8 {
        if (platform != .browser) return null;
        const real_js = @import("js");
        const event = self.getEvent();
        const target = event.ref.get(real_js.Object, "target") catch return null;
        return target.getAlloc(real_js.String, client_allocator, "value") catch null;
    }

    /// Get the key from keyboard event
    pub fn key(self: EventContext) ?[]const u8 {
        if (platform != .browser) return null;
        const real_js = @import("js");
        const event = self.getEvent();
        return event.ref.getAlloc(real_js.String, client_allocator, "key") catch null;
    }
};

pub const ActionContext = struct {
    request: Request,
    response: Response,
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    action_ref: u64,
    pub fn init(action_ref: u64) ActionContext {
        return .{ .action_ref = action_ref };
    }
};
