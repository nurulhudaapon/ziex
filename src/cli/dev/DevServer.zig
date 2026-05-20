/// DevServer - a lightweight proxy that owns the user-facing port so it never, this is based on WebServer.zig reom Zig std
/// drops during app binary restarts, and provides a stable WebSocket endpoint
/// for hot-reload signals and error overlays.
///
/// Architecture:
///   Browser ──HTTP──► DevServer (outer_port, stays alive)
///                         ├─ /.well-known/_zx/  → WebSocket and related assets (served here)
///                         └─ everything else    → proxy → app binary (inner_port)
///
/// WebSocket messages sent to browsers are JSON-serialized `Notification`
/// values. `dev.zig` decides which notification to send; DevServer just
/// serializes, queues, and broadcasts them.
const std = @import("std");
const builtin = @import("builtin");
const http = std.http;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.devserver);

/// Minimal HTML shell served when the inner app is not running (e.g. initial
/// build errors). It includes the devscript so the browser can connect to the
/// DevServer WebSocket and display the error overlay immediately.
const ERROR_SHELL_HTML = @embedFile("errorshell.html");
const DEVSCRIPT_JS = @embedFile("devscript.js");

const DevServer = @This();

pub const Notification = struct {
    type: Type,
    message: ?[]const u8 = null,
    diagnostics: ?[]const Diagnostic = null,
    files: ?[]const []const u8 = null,

    pub const Type = enum {
        connected,
        reload,
        @"error",
        clear,
        building,
        asset_update,
    };

    pub const Kind = enum {
        @"error",
        warning,
        note,
    };

    pub const Diagnostic = struct {
        file: []const u8,
        line: u32,
        col: u32,
        kind: Kind,
        message: []const u8,
        source: ?[]const u8 = null,
        source_html: ?[]const u8 = null,
    };
};

const QueuedEvent = struct {
    json: []u8,
};

const EVENT_QUEUE_CAP = 16;

io: std.Io,
gpa: Allocator,
env_map: *const std.process.Environ.Map,
address: std.Io.net.IpAddress,
inner_port: u16,
tcp_server: ?std.Io.net.Server,
serve_thread: ?std.Thread,

/// Incremented on each event. WebSocket threads block on this with Futex.
update_id: std.atomic.Value(u32),

/// Bounded event queue so rapid transitions (building → reload) don't drop events.
event_mutex: std.Io.Mutex,
event_queue: [EVENT_QUEUE_CAP]QueuedEvent = undefined,
event_head: u32 = 0, // next write position
event_tail: u32 = 0, // next read position
sticky_state_json: ?[]u8 = null,

pub const Options = struct {
    io: std.Io,
    gpa: Allocator,
    env_map: *const std.process.Environ.Map,
    /// Address to bind the user-facing proxy to.
    address: std.Io.net.IpAddress,
    /// Port the app binary will listen on.
    inner_port: u16,
};

pub fn init(opts: Options) DevServer {
    log.debug("devserver init port: {d}", .{opts.address.getPort()});
    return .{
        .gpa = opts.gpa,
        .env_map = opts.env_map,
        .address = opts.address,
        .inner_port = opts.inner_port,
        .tcp_server = null,
        .serve_thread = null,
        .update_id = .init(0),
        .event_mutex = .init,
        .io = opts.io,
    };
}

pub fn deinit(ds: *DevServer) void {
    if (ds.serve_thread) |t| {
        if (ds.tcp_server) |*s| s.socket.close(ds.io);
        t.join();
    }
    if (ds.tcp_server) |*s| s.deinit(ds.io);
    // Drain any remaining queued events
    while (ds.event_tail != ds.event_head) {
        const idx = ds.event_tail % EVENT_QUEUE_CAP;
        ds.gpa.free(ds.event_queue[idx].json);
        ds.event_tail +%= 1;
    }
    if (ds.sticky_state_json) |json| {
        ds.gpa.free(json);
    }
}

pub fn start(ds: *DevServer) error{AlreadyReported}!void {
    assert(ds.tcp_server == null);
    assert(ds.serve_thread == null);

    log.debug("devserver start", .{});

    ds.tcp_server = ds.address.listen(ds.io, .{ .reuse_address = true }) catch |err| {
        log.err("failed to listen on {f}: {s}", .{ ds.address, @errorName(err) });
        return error.AlreadyReported;
    };
    ds.serve_thread = std.Thread.spawn(.{}, serve, .{ds}) catch |err| {
        log.err("unable to spawn dev server thread: {s}", .{@errorName(err)});
        ds.tcp_server.?.deinit(ds.io);
        ds.tcp_server = null;
        return error.AlreadyReported;
    };
}

/// Push a serialized notification onto the queue and wake WS threads.
/// Thread-safe.
fn pushEvent(ds: *DevServer, json: []u8) void {
    const io = std.Io.Threaded.global_single_threaded.io();
    ds.event_mutex.lockUncancelable(io);
    const idx = ds.event_head % EVENT_QUEUE_CAP;
    // If queue is full, drop oldest event
    if (ds.event_head -% ds.event_tail >= EVENT_QUEUE_CAP) {
        const old_idx = ds.event_tail % EVENT_QUEUE_CAP;
        ds.gpa.free(ds.event_queue[old_idx].json);
        ds.event_tail +%= 1;
    }
    ds.event_queue[idx] = .{ .json = json };
    ds.event_head +%= 1;
    ds.event_mutex.unlock(io);
    _ = ds.update_id.rmw(.Add, 1, .release);
    io.futexWake(u32, &ds.update_id.raw, std.math.maxInt(u32));
}

pub fn notify(ds: *DevServer, notification: Notification) void {
    const json = serializeNotification(ds.gpa, notification) catch return;
    ds.updateStickyState(notification, json);
    ds.pushEvent(json);
}

fn updateStickyState(ds: *DevServer, notification: Notification, json: []const u8) void {
    const io = std.Io.Threaded.global_single_threaded.io();
    ds.event_mutex.lockUncancelable(io);
    defer ds.event_mutex.unlock(io);

    switch (notification.type) {
        .building, .@"error" => {
            const duplicated = ds.gpa.dupe(u8, json) catch return;
            if (ds.sticky_state_json) |prev| ds.gpa.free(prev);
            ds.sticky_state_json = duplicated;
        },
        .clear, .reload, .connected, .asset_update => {
            if (ds.sticky_state_json) |prev| {
                ds.gpa.free(prev);
                ds.sticky_state_json = null;
            }
        },
    }
}

/// Find a free OS-assigned port by briefly binding to port 0.
pub fn findFreePort() !u16 {
    const io = std.Io.Threaded.global_single_threaded.io();
    var server = try (try std.Io.net.IpAddress.parse("127.0.0.1", 0)).listen(io, .{});
    defer server.deinit(io);
    return server.socket.address.getPort();
}

fn serve(ds: *DevServer) void {
    var retry_count: u8 = 0;

    while (true) {
        const connection = ds.tcp_server.?.accept(ds.io) catch |err| {
            switch (err) {
                error.Unexpected => {
                    retry_count += 1;
                    if (retry_count > 5) {
                        log.err("accept() failed {d} times, giving up: {s}", .{ retry_count - 1, @errorName(err) });
                        return;
                    }
                    log.warn("accept() failed (transient): {s}", .{@errorName(err)});
                    std.Io.sleep(ds.io, .fromMilliseconds(50), .awake) catch {};
                    continue;
                },
                else => {
                    log.err("failed to accept connection: {s}", .{@errorName(err)});
                    return;
                },
            }
        };
        retry_count = 0;
        const thread = std.Thread.spawn(.{}, handleConnection, .{ ds, connection }) catch |err| {
            log.err("unable to spawn connection thread: {s}", .{@errorName(err)});
            connection.close(ds.io);
            continue;
        };
        thread.detach();
    }
}

fn handleConnection(ds: *DevServer, stream: std.Io.net.Stream) void {
    defer stream.close(ds.io);

    // Connection accepted
    log.debug("connection accepted", .{});

    var send_buffer: [4096]u8 = undefined;
    var recv_buffer: [4096]u8 = undefined;
    var connection_reader = stream.reader(ds.io, &recv_buffer);
    var connection_writer = stream.writer(ds.io, &send_buffer);
    var server: http.Server = .init(&connection_reader.interface, &connection_writer.interface);

    while (true) {
        var request = server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => return,
            else => return log.debug("failed to receive http request: {s}", .{@errorName(err)}),
        };

        switch (request.upgradeRequested()) {
            .websocket => |opt_key| {
                const key = opt_key orelse return log.err("missing websocket key", .{});
                var web_socket = request.respondWebSocket(.{ .key = key }) catch {
                    return log.err("failed to respond web socket", .{});
                };
                serveWebSocket(ds, &web_socket) catch |err| {
                    log.debug("failed to serve websocket: {s}", .{@errorName(err)});
                    return;
                };
                return;
            },
            .other => |name| return log.err("unknown upgrade request: {s}", .{name}),
            .none => {
                ds.serveRequest(&request, stream) catch |err| switch (err) {
                    error.AlreadyReported => return,
                    else => {
                        log.err("failed to serve '{s}': {s}", .{ request.head.target, @errorName(err) });
                        return;
                    },
                };
            },
        }
    }
}

fn serveRequest(ds: *DevServer, req: *http.Server.Request, client_stream: std.Io.net.Stream) !void {
    const target = req.head.target;
    var target_split = std.mem.splitScalar(u8, target, '?');
    const target_path = target_split.first();

    // 1. Intercept system requests (dev server only)
    if (std.mem.startsWith(u8, target_path, "/.well-known/_zx/")) {
        if (std.mem.eql(u8, target_path, "/.well-known/_zx/devscript.js")) {
            log.debug("devscript matched: {s}", .{target});
            try req.respond(DEVSCRIPT_JS, .{
                .extra_headers = &.{
                    .{ .name = "Content-Type", .value = "application/javascript" },
                    .{ .name = "Cache-Control", .value = "no-cache" },
                    .{ .name = "Connection", .value = "close" },
                },
            });
            return;
        }

        if (std.mem.eql(u8, target_path, "/.well-known/_zx/open-in-editor")) {
            log.debug("open-in-editor matched: {s}", .{target});
            handleOpenInEditor(ds, target) catch |err| {
                log.debug("handleOpenInEditor failed: {s}", .{@errorName(err)});
            };
            try req.respond("", .{
                .extra_headers = &.{
                    .{ .name = "Connection", .value = "close" },
                },
            });
            return;
        }
    }

    // 2. Everything else goes to the inner app
    log.debug("proxyToInner: {s}", .{target});
    const buffered_extra = req.server.reader.in.buffer[req.server.reader.in.seek..req.server.reader.in.end];

    // For app proxying, we currently only proxy ONE request per connection.
    // This is because proxyToInner pipes raw streams.
    proxyToInner(ds, client_stream, req.head_buffer, buffered_extra) catch |err| {
        // If the inner app isn't running (build errors, first startup, etc.),
        // serve a minimal HTML shell with the devscript embedded so the
        // browser can connect to the WebSocket and display error overlays.
        log.debug("proxyToInner failed ({s}), serving error shell", .{@errorName(err)});
        try req.respond(ERROR_SHELL_HTML, .{
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "text/html; charset=utf-8" },
                .{ .name = "Cache-Control", .value = "no-cache, no-store" },
                .{ .name = "Connection", .value = "close" },
            },
        });
        return error.AlreadyReported;
    };

    // After proxyToInner returns, the connection is typically exhausted.
    return error.AlreadyReported;
}

fn serveWebSocket(ds: *DevServer, sock: *http.Server.WebSocket) !noreturn {
    // Send initial connected message (also flushes the 101 handshake response).
    log.debug("ws: sending connected message", .{});
    const connected = try serializeNotification(ds.gpa, .{ .type = .connected });
    defer ds.gpa.free(connected);
    sock.writeMessage(connected, .text) catch |err| {
        log.err("ws: failed to send connected message: {s}", .{@errorName(err)});
        return err;
    };
    log.debug("ws: connected message sent", .{});

    // Drain incoming frames on a dedicated thread - mirrors WebServer.zig's
    // recvWebSocketMessages pattern. Without this, the connection stalls because
    // unread frames (pings, close frames, etc.) block the underlying TCP stream.
    const recv_thread = std.Thread.spawn(.{}, recvWebSocketFrames, .{sock}) catch |err| {
        log.err("ws: failed to spawn recv thread: {s}", .{@errorName(err)});
        return err;
    };
    defer recv_thread.join();
    log.debug("ws: recv thread spawned, entering event loop", .{});

    const io = std.Io.Threaded.global_single_threaded.io();
    var sticky_snapshot: ?[]u8 = null;
    var last_id: u32 = 0;
    ds.event_mutex.lockUncancelable(io);
    last_id = ds.event_head;
    if (ds.sticky_state_json) |json| {
        sticky_snapshot = ds.gpa.dupe(u8, json) catch null;
    }
    ds.event_mutex.unlock(io);

    if (sticky_snapshot) |json| {
        defer ds.gpa.free(json);
        try sock.writeMessage(json, .text);
    }

    while (true) {
        const cur = ds.update_id.load(.acquire);
        if (cur == last_id) {
            // No pending event - wait up to 30 s then ping to keep the connection alive.
            io.futexWaitTimeout(u32, &ds.update_id.raw, last_id, .{ .duration = .{ .raw = .{ .nanoseconds = 30 * std.time.ns_per_s }, .clock = .awake } }) catch {
                try sock.writeMessage("", .ping);
                continue;
            };
            continue;
        }

        // Read the current event under the lock, then release before I/O.
        ds.event_mutex.lockUncancelable(io);
        const head = ds.event_head;
        if (head == last_id) {
            ds.event_mutex.unlock(io);
            continue;
        }
        if (head -% last_id > EVENT_QUEUE_CAP) {
            last_id = head - EVENT_QUEUE_CAP;
        }
        const event_index = last_id % EVENT_QUEUE_CAP;
        const json_copy = ds.gpa.dupe(u8, ds.event_queue[event_index].json) catch {
            ds.event_mutex.unlock(io);
            last_id +%= 1;
            continue;
        };
        ds.event_mutex.unlock(io);

        last_id +%= 1;

        defer ds.gpa.free(json_copy);
        try sock.writeMessage(json_copy, .text);
    }
}

/// Continuously reads and discards incoming WebSocket frames so the TCP receive
/// buffer never fills up and control frames (pings, close) are consumed.
fn recvWebSocketFrames(sock: *http.Server.WebSocket) void {
    log.debug("ws: recv thread started", .{});
    while (true) {
        const msg = sock.readSmallMessage() catch |err| {
            log.debug("ws: recv thread exiting: {s}", .{@errorName(err)});
            return;
        };
        log.debug("ws: received frame opcode={s} len={d}", .{ @tagName(msg.opcode), msg.data.len });
    }
}

fn serializeNotification(gpa: Allocator, notification: Notification) ![]u8 {
    return std.fmt.allocPrint(gpa, "{f}", .{
        std.json.fmt(notification, .{
            .emit_null_optional_fields = false,
        }),
    });
}

/// Proxy a request to the inner app binary.
/// `head_buffer`     - raw HTTP request head (including terminating \r\n\r\n).
/// `buffered_extra`  - body bytes already consumed by the http.Server reader.
fn proxyToInner(
    ds: *DevServer,
    client: std.Io.net.Stream,
    head_buffer: []const u8,
    buffered_extra: []const u8,
) !void {
    const inner_addr = try std.Io.net.IpAddress.parse("127.0.0.1", ds.inner_port);

    // Retry while the inner server is (re)starting - up to 2 s.
    const inner: std.Io.net.Stream = for (0..200) |_| {
        if (inner_addr.connect(ds.io, .{ .mode = .stream })) |s| break s else |_| std.Io.sleep(ds.io, .fromMicroseconds(10), .real) catch {};
    } else return error.ConnectionRefused;
    defer inner.close(ds.io);
    // We MUST force the inner server to close the connection, otherwise the browser
    // will try to reuse this connection (which we are currently piping raw)
    // for subsequent requests that might need to be intercepted by the DevServer.

    // Find the end of headers
    const end_idx = std.mem.indexOf(u8, head_buffer, "\r\n\r\n") orelse head_buffer.len;
    const header_part = head_buffer[0..end_idx];

    var transformed = std.ArrayList(u8).empty;
    defer transformed.deinit(ds.gpa);

    const keep_alive = "keep-alive";
    const close = "close";

    if (std.mem.indexOf(u8, header_part, keep_alive) != null) {
        const count = std.mem.count(u8, header_part, keep_alive);
        const new_len = header_part.len - (count * (keep_alive.len - close.len));
        try transformed.resize(ds.gpa, new_len);
        _ = std.mem.replace(u8, header_part, keep_alive, close, transformed.items);
    } else if (std.mem.indexOf(u8, header_part, "Connection:") == null) {
        try transformed.appendSlice(ds.gpa, header_part);
        try transformed.appendSlice(ds.gpa, "\r\nConnection: close");
    } else {
        try transformed.appendSlice(ds.gpa, header_part);
    }
    try transformed.appendSlice(ds.gpa, "\r\n\r\n");

    var inner_writer_buf: [4096]u8 = undefined;
    var inner_writer = inner.writer(ds.io, &inner_writer_buf);
    try inner_writer.interface.writeAll(transformed.items);

    // Forward any body bytes already buffered by the http.Server reader.
    if (buffered_extra.len > 0) try inner_writer.interface.writeAll(buffered_extra);
    try inner_writer.interface.flush();

    // Windows can report ERROR_INVALID_PARAMETER from ReadFile when combining
    // this shutdown-based bidirectional copy pattern with sockets. Use a
    // simpler one-way response copy there.
    if (builtin.os.tag == .windows) {
        copyStream(ds.io, inner, client);
        return;
    }

    // Bidirectional pipe: remaining request body client→inner, response inner→client.
    // The inner→client thread shuts down the client write side when inner closes,
    // which unblocks the client→inner copy loop below.
    const fwd = std.Thread.spawn(.{}, copyStreamThenShutdown, .{ ds.io, inner, client }) catch return;
    defer fwd.join();

    copyStream(ds.io, client, inner);

    // Unblock the inner→client thread if client closed first.
    inner.shutdown(ds.io, .recv) catch {};
}

/// Copy src→dst, then shut down the dst send side so the peer's read unblocks.
fn copyStreamThenShutdown(io: std.Io, src: std.Io.net.Stream, dst: std.Io.net.Stream) void {
    copyStream(io, src, dst);
    dst.shutdown(io, .send) catch {};
}

fn copyStream(io: std.Io, src: std.Io.net.Stream, dst: std.Io.net.Stream) void {
    var read_buf: [65536]u8 = undefined;
    var reader_state: [1024]u8 = undefined;
    var writer_state: [1024]u8 = undefined;
    var reader = src.reader(io, &reader_state);
    var writer = dst.writer(io, &writer_state);

    while (true) {
        const n = reader.interface.readSliceShort(&read_buf) catch return;
        if (n == 0) return;
        writer.interface.writeAll(read_buf[0..n]) catch return;
        writer.interface.flush() catch return;
    }
}

// Diagnostics integration
fn handleOpenInEditor(ds: *DevServer, target: []const u8) !void {
    const query_pos = std.mem.indexOf(u8, target, "?") orelse return;
    const query = target[query_pos + 1 ..];

    var it = std.mem.splitScalar(u8, query, '&');
    var file: ?[]const u8 = null;
    var line: ?[]const u8 = null;
    var col: ?[]const u8 = null;

    while (it.next()) |pair| {
        if (std.mem.startsWith(u8, pair, "file=")) {
            file = pair[5..];
        } else if (std.mem.startsWith(u8, pair, "line=")) {
            line = pair[5..];
        } else if (std.mem.startsWith(u8, pair, "col=")) {
            col = pair[4..];
        }
    }

    if (file) |f_enc| {
        const decoded_file = try urlDecode(ds.gpa, f_enc);
        defer ds.gpa.free(decoded_file);

        const l = line orelse "1";
        const c = col orelse "1";

        const file_arg = try std.fmt.allocPrint(ds.gpa, "{s}:{s}:{s}", .{ decoded_file, l, c });
        defer ds.gpa.free(file_arg);

        const args = try IdeScheme.detect(ds.gpa, ds.env_map, decoded_file, l, c);
        defer {
            for (args) |arg| ds.gpa.free(arg);
            ds.gpa.free(args);
        }

        if (args.len == 0) return;
        log.debug("opening in editor: {s}", .{args[0]});

        var child_proc = std.process.spawn(ds.io, .{
            .argv = args,
            .stdin = .ignore,
            .stdout = .ignore,
            .stderr = .ignore,
        }) catch |err| {
            log.debug("editor failed to spawn: {s}", .{@errorName(err)});
            return;
        };
        _ = child_proc.wait(ds.io) catch {};
    }
}

fn urlDecode(allocator: std.mem.Allocator, encoded: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < encoded.len) {
        if (encoded[i] == '%' and i + 2 < encoded.len) {
            const hex = encoded[i + 1 .. i + 3];
            const byte = std.fmt.parseInt(u8, hex, 16) catch {
                try out.append(allocator, encoded[i]);
                i += 1;
                continue;
            };
            try out.append(allocator, byte);
            i += 3;
        } else {
            try out.append(allocator, encoded[i]);
            i += 1;
        }
    }
    return out.toOwnedSlice(allocator);
}

const IdeScheme = @import("IdeScheme.zig");
