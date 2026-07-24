const std = @import("std");
const Request = @import("Request.zig");
const Response = @import("Response.zig");
const Http = @import("Http.zig");

pub const BaseContext = struct {
    const Self = @This();

    /// The HTTP request object (backend-agnostic)
    request: Request,
    /// The HTTP response object (backend-agnostic)
    response: Response,
    /// Global allocator passed from the app, only cleared when the app is deinitialized.
    allocator: std.mem.Allocator,
    /// Arena allocator cleared automatically after the request is processed.
    arena: std.mem.Allocator,
    /// Process I/O passed to `App.init` by the user.
    io: std.Io,

    pub fn init(request: Request, response: Response, alloc: std.mem.Allocator, io: std.Io) Self {
        return .{
            .request = request,
            .response = response,
            .allocator = alloc,
            .arena = request.arena,
            .io = io,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    pub fn fmt(self: Self, comptime format: []const u8, args: anytype) ![]u8 {
        return fmtInner(self.arena, format, args);
    }
};

/// Context passed to page components. Provides access to the current HTTP request and response,
/// as well as allocators for memory management.
///
/// Usage in a page component:
/// ```zig
/// pub fn Page(ctx: zx.PageContext) zx.Component {
///     const allocator = ctx.arena; // Use arena for temporary allocations
///     // Access request data via MDN-compliant API
///     const method = ctx.request.method;
///     const url = ctx.request.url;
///     // Render component
///     return <div>Hello</div>;
/// }
/// ```
pub const PageContext = BaseContext;

/// Context passed to layout components. Provides access to the current HTTP request and response,
/// as well as allocators for memory management. Layouts wrap page components and can be nested.
///
/// Usage in a layout component:
/// ```zig
/// pub fn Layout(ctx: zx.LayoutContext, children: zx.Component) zx.Component {
///     return (
///         <html>
///             <head><title>My App</title></head>
///             <body>{children}</body>
///         </html>
///     );
/// }
/// ```
pub const LayoutContext = BaseContext;
pub const NotFoundContext = BaseContext;

pub const ErrorContext = struct {
    /// The HTTP request object (backend-agnostic)
    request: Request,
    /// The HTTP response object (backend-agnostic)
    response: Response,
    /// Global allocator
    allocator: std.mem.Allocator,
    /// Arena allocator for request-scoped allocations
    arena: std.mem.Allocator,
    /// Process I/O passed to `App.init` by the user.
    io: std.Io,
    /// The error that occurred
    err: anyerror,

    pub fn init(request: Request, response: Response, alloc: std.mem.Allocator, io: std.Io, err: anyerror) ErrorContext {
        return .{
            .request = request,
            .response = response,
            .allocator = alloc,
            .arena = request.arena,
            .io = io,
            .err = err,
        };
    }

    pub fn deinit(self: *ErrorContext) void {
        self.allocator.destroy(self);
    }
};

/// Socket options for configuring WebSocket behavior
pub const SocketOptions = struct {
    /// When true, publish() will also send the message to the sender.
    /// Default is false (sender is excluded from publish).
    publish_to_self: bool = false,
};

pub const Socket = struct {
    _internal: Internal = .{},

    pub const Internal = struct {
        http: Http = .{},
        /// Whether a real backend has been attached (i.e. the route can upgrade).
        attached: bool = false,
    };

    pub fn upgrade(self: Socket, data: anytype) !void {
        if (!self._internal.attached) return;
        const DataType = @TypeOf(data);
        if (DataType == void) {
            try self._internal.http.wsUpgrade(null);
        } else {
            try self._internal.http.wsUpgrade(std.mem.asBytes(&data));
        }
    }

    /// Write data to the WebSocket connection.
    /// This should be called from the Socket handler to send messages.
    pub fn write(self: Socket, data: []const u8) !void {
        if (!self._internal.attached) return;
        try self._internal.http.wsWrite(data);
    }

    pub fn read(self: Socket) ?[]const u8 {
        if (!self._internal.attached) return null;
        return self._internal.http.wsRead();
    }

    /// Close the WebSocket connection.
    pub fn close(self: Socket) void {
        if (!self._internal.attached) return;
        self._internal.http.wsClose();
    }

    /// Returns true if this socket has been upgraded to a WebSocket connection.
    pub fn isUpgraded(self: Socket) bool {
        return self._internal.attached;
    }

    /// Subscribe to a topic to receive published messages.
    /// Multiple sockets can subscribe to the same topic.
    ///
    /// Example:
    /// ```zig
    /// ctx.socket.subscribe("chat-room");
    /// ctx.socket.subscribe("notifications");
    /// ```
    pub fn subscribe(self: Socket, topic: []const u8) void {
        if (!self._internal.attached) return;
        self._internal.http.wsSubscribe(topic);
    }

    /// Unsubscribe from a topic to stop receiving messages.
    ///
    /// Example:
    /// ```zig
    /// ctx.socket.unsubscribe("chat-room");
    /// ```
    pub fn unsubscribe(self: Socket, topic: []const u8) void {
        if (!self._internal.attached) return;
        self._internal.http.wsUnsubscribe(topic);
    }

    /// Publish a message to all subscribers of a topic, excluding the sender.
    /// Returns the number of sockets the message was sent to.
    ///
    /// Example:
    /// ```zig
    /// const sent = ctx.socket.publish("chat-room", "Hello everyone!");
    /// ```
    pub fn publish(self: Socket, topic: []const u8, message: []const u8) usize {
        if (!self._internal.attached) return 0;
        return self._internal.http.wsPublish(topic, message);
    }

    /// Check if this socket is subscribed to a topic.
    ///
    /// Example:
    /// ```zig
    /// if (ctx.socket.isSubscribed("chat-room")) {
    ///     // ...
    /// }
    /// ```
    pub fn isSubscribed(self: Socket, topic: []const u8) bool {
        if (!self._internal.attached) return false;
        return self._internal.http.wsIsSubscribed(topic);
    }

    /// Configure whether publish() sends to self.
    ///
    /// Example:
    /// ```zig
    /// ctx.socket.setPublishToSelf(true);
    /// // Now publish() will include the sender
    /// ```
    pub fn setPublishToSelf(self: Socket, value: bool) void {
        if (!self._internal.attached) return;
        self._internal.http.wsSetPublishToSelf(value);
    }

    /// Configure socket options.
    ///
    /// Example:
    /// ```zig
    /// ctx.socket.configure(.{ .publish_to_self = true });
    /// ```
    pub fn configure(self: Socket, options: SocketOptions) void {
        self.setPublishToSelf(options.publish_to_self);
    }
};

/// Route context. App context and proxy-set state are injected positionally
/// by the wrapRoute() wrapper, not exposed as fields here.
pub const RouteContext = struct {
    const Self = @This();

    request: Request,
    response: Response,
    socket: Socket,
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    /// Process I/O passed to `App.init` by the user.
    io: std.Io,

    pub fn init(request: Request, response: Response, alloc: std.mem.Allocator, io: std.Io) Self {
        return .{
            .request = request,
            .response = response,
            .socket = .{},
            .allocator = alloc,
            .arena = request.arena,
            .io = io,
        };
    }

    pub fn initWithSocket(request: Request, response: Response, socket: Socket, alloc: std.mem.Allocator, io: std.Io) Self {
        return .{
            .request = request,
            .response = response,
            .socket = socket,
            .allocator = alloc,
            .arena = request.arena,
            .io = io,
        };
    }

    pub fn fmt(self: Self, comptime format: []const u8, args: anytype) ![]u8 {
        return fmtInner(self.arena, format, args);
    }
};

/// Message type for WebSocket messages (text vs binary)
pub const SocketMessageType = enum {
    text,
    binary,
};

/// Context for WebSocket message handlers (Socket function).
/// This is the primary handler called for each message received.
pub const SocketContext = SocketCtx(void);

/// Context for WebSocket handlers with custom data passed during upgrade.
/// Use SocketCtx(YourDataType) to access data passed via ctx.socket.upgrade(data).
pub fn SocketCtx(comptime DataType: type) type {
    return struct {
        /// The WebSocket connection for sending messages
        socket: Socket,
        /// The client message data (received from WebSocket)
        message: []const u8,
        /// The message type (text or binary)
        message_type: SocketMessageType,
        /// Custom data passed from upgrade handler
        data: DataType,
        /// Global allocator
        allocator: std.mem.Allocator,
        /// Arena allocator for request-scoped allocations
        arena: std.mem.Allocator,
        /// Process I/O passed to `App.init` by the user.
        io: std.Io,

        const Self = @This();

        pub fn fmt(self: Self, comptime format: []const u8, args: anytype) ![]u8 {
            return fmtInner(self.arena, format, args);
        }
    };
}

/// Context for SocketOpen handlers (called when connection opens).
/// Same structure as SocketCtx but without message data.
pub const SocketOpenContext = SocketOpenCtx(void);

pub fn SocketOpenCtx(comptime DataType: type) type {
    return struct {
        /// The WebSocket connection for sending messages
        socket: Socket,
        /// Custom data passed from upgrade handler
        data: DataType,
        /// Global allocator
        allocator: std.mem.Allocator,
        /// Arena allocator for request-scoped allocations
        arena: std.mem.Allocator,
        /// Process I/O passed to `App.init` by the user.
        io: std.Io,

        const Self = @This();

        pub fn fmt(self: Self, comptime format: []const u8, args: anytype) ![]u8 {
            return fmtInner(self.arena, format, args);
        }
    };
}

/// Context for SocketClose handlers (called when connection closes).
/// Same structure as SocketOpenCtx.
pub const SocketCloseContext = SocketCloseCtx(void);

pub fn SocketCloseCtx(comptime DataType: type) type {
    return struct {
        /// The WebSocket connection (may not be writable)
        socket: Socket,
        /// Custom data passed from upgrade handler
        data: DataType,
        /// Global allocator
        allocator: std.mem.Allocator,
        /// Arena allocator for request-scoped allocations
        arena: std.mem.Allocator,
        /// Process I/O passed to `App.init` by the user.
        io: std.Io,

        const Self = @This();

        pub fn fmt(self: Self, comptime format: []const u8, args: anytype) ![]u8 {
            return fmtInner(self.arena, format, args);
        }
    };
}

inline fn fmtInner(allocator: std.mem.Allocator, comptime format: []const u8, args: anytype) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    aw.writer.print(format, args) catch |err| switch (err) {
        error.WriteFailed => return error.OutOfMemory,
    };
    return aw.toOwnedSlice();
}
