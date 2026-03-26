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

    pub const Type = enum {
        connected,
        reload,
        @"error",
        clear,
        building,
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

gpa: Allocator,
address: std.net.Address,
inner_port: u16,
tcp_server: ?std.net.Server,
serve_thread: ?std.Thread,

/// Incremented on each event. WebSocket threads block on this with Futex.
update_id: std.atomic.Value(u32),

/// Bounded event queue so rapid transitions (building → reload) don't drop events.
event_mutex: std.Thread.Mutex,
event_queue: [EVENT_QUEUE_CAP]QueuedEvent = undefined,
event_head: u32 = 0, // next write position
event_tail: u32 = 0, // next read position
sticky_state_json: ?[]u8 = null,

pub const Options = struct {
    gpa: Allocator,
    /// Address to bind the user-facing proxy to.
    address: std.net.Address,
    /// Port the app binary will listen on.
    inner_port: u16,
};

pub fn init(opts: Options) DevServer {
    log.debug("devserver init port: {d}", .{opts.address.getPort()});
    return .{
        .gpa = opts.gpa,
        .address = opts.address,
        .inner_port = opts.inner_port,
        .tcp_server = null,
        .serve_thread = null,
        .update_id = .init(0),
        .event_mutex = .{},
    };
}

pub fn deinit(ds: *DevServer) void {
    if (ds.serve_thread) |t| {
        if (ds.tcp_server) |*s| s.stream.close();
        t.join();
    }
    if (ds.tcp_server) |*s| s.deinit();
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

    ds.tcp_server = ds.address.listen(.{ .reuse_address = true }) catch |err| {
        log.err("failed to listen on {f}: {s}", .{ ds.address, @errorName(err) });
        return error.AlreadyReported;
    };
    ds.serve_thread = std.Thread.spawn(.{}, serve, .{ds}) catch |err| {
        log.err("unable to spawn dev server thread: {s}", .{@errorName(err)});
        ds.tcp_server.?.deinit();
        ds.tcp_server = null;
        return error.AlreadyReported;
    };
}

/// Push a serialized notification onto the queue and wake WS threads.
/// Thread-safe.
fn pushEvent(ds: *DevServer, json: []u8) void {
    ds.event_mutex.lock();
    const idx = ds.event_head % EVENT_QUEUE_CAP;
    // If queue is full, drop oldest event
    if (ds.event_head -% ds.event_tail >= EVENT_QUEUE_CAP) {
        const old_idx = ds.event_tail % EVENT_QUEUE_CAP;
        ds.gpa.free(ds.event_queue[old_idx].json);
        ds.event_tail +%= 1;
    }
    ds.event_queue[idx] = .{ .json = json };
    ds.event_head +%= 1;
    ds.event_mutex.unlock();
    _ = ds.update_id.rmw(.Add, 1, .release);
    std.Thread.Futex.wake(&ds.update_id, std.math.maxInt(u32));
}

pub fn notify(ds: *DevServer, notification: Notification) void {
    const json = serializeNotification(ds.gpa, notification) catch return;
    ds.updateStickyState(notification, json);
    ds.pushEvent(json);
}

fn updateStickyState(ds: *DevServer, notification: Notification, json: []const u8) void {
    ds.event_mutex.lock();
    defer ds.event_mutex.unlock();

    switch (notification.type) {
        .building, .@"error" => {
            const duplicated = ds.gpa.dupe(u8, json) catch return;
            if (ds.sticky_state_json) |prev| ds.gpa.free(prev);
            ds.sticky_state_json = duplicated;
        },
        .clear, .reload, .connected => {
            if (ds.sticky_state_json) |prev| {
                ds.gpa.free(prev);
                ds.sticky_state_json = null;
            }
        },
    }
}

/// Find a free OS-assigned port by briefly binding to port 0.
pub fn findFreePort() !u16 {
    var server = try (try std.net.Address.parseIp("127.0.0.1", 0)).listen(.{});
    defer server.deinit();
    return server.listen_address.getPort();
}

fn serve(ds: *DevServer) void {
    while (true) {
        const connection = ds.tcp_server.?.accept() catch |err| {
            log.err("failed to accept connection: {s}", .{@errorName(err)});
            return;
        };
        _ = std.Thread.spawn(.{}, handleConnection, .{ ds, connection }) catch |err| {
            log.err("unable to spawn connection thread: {s}", .{@errorName(err)});
            connection.stream.close();
            continue;
        };
    }
}

fn handleConnection(ds: *DevServer, conn: std.net.Server.Connection) void {
    defer conn.stream.close();

    // Get a formatted IP string to avoid ambiguity in std.log
    var addr_buf: [64]u8 = undefined;
    const addr_str = std.fmt.bufPrint(&addr_buf, "{any}", .{conn.address}) catch "unknown";
    log.debug("connection accepted from {s}", .{addr_str});

    var send_buffer: [4096]u8 = undefined;
    var recv_buffer: [4096]u8 = undefined;
    var connection_reader = conn.stream.reader(&recv_buffer);
    var connection_writer = conn.stream.writer(&send_buffer);
    var server: http.Server = .init(connection_reader.interface(), &connection_writer.interface);

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
                ds.serveRequest(&request, conn.stream) catch |err| switch (err) {
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

fn serveRequest(ds: *DevServer, req: *http.Server.Request, client_stream: std.net.Stream) !void {
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

    // Drain incoming frames on a dedicated thread — mirrors WebServer.zig's
    // recvWebSocketMessages pattern. Without this, the connection stalls because
    // unread frames (pings, close frames, etc.) block the underlying TCP stream.
    const recv_thread = std.Thread.spawn(.{}, recvWebSocketFrames, .{sock}) catch |err| {
        log.err("ws: failed to spawn recv thread: {s}", .{@errorName(err)});
        return err;
    };
    defer recv_thread.join();
    log.debug("ws: recv thread spawned, entering event loop", .{});

    var sticky_snapshot: ?[]u8 = null;
    var last_id: u32 = 0;
    ds.event_mutex.lock();
    last_id = ds.event_head;
    if (ds.sticky_state_json) |json| {
        sticky_snapshot = ds.gpa.dupe(u8, json) catch null;
    }
    ds.event_mutex.unlock();

    if (sticky_snapshot) |json| {
        defer ds.gpa.free(json);
        try sock.writeMessage(json, .text);
    }

    while (true) {
        const cur = ds.update_id.load(.acquire);
        if (cur == last_id) {
            // No pending event — wait up to 30 s then ping to keep the connection alive.
            std.Thread.Futex.timedWait(&ds.update_id, last_id, 30 * std.time.ns_per_s) catch {
                try sock.writeMessage("", .ping);
                continue;
            };
            continue;
        }

        // Read the current event under the lock, then release before I/O.
        ds.event_mutex.lock();
        const head = ds.event_head;
        if (head == last_id) {
            ds.event_mutex.unlock();
            continue;
        }
        if (head -% last_id > EVENT_QUEUE_CAP) {
            last_id = head - EVENT_QUEUE_CAP;
        }
        const event_index = last_id % EVENT_QUEUE_CAP;
        const json_copy = ds.gpa.dupe(u8, ds.event_queue[event_index].json) catch {
            ds.event_mutex.unlock();
            last_id +%= 1;
            continue;
        };
        ds.event_mutex.unlock();

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
/// `head_buffer`     — raw HTTP request head (including terminating \r\n\r\n).
/// `buffered_extra`  — body bytes already consumed by the http.Server reader.
fn proxyToInner(
    ds: *DevServer,
    client: std.net.Stream,
    head_buffer: []const u8,
    buffered_extra: []const u8,
) !void {
    const inner_addr = try std.net.Address.parseIp("127.0.0.1", ds.inner_port);

    // Retry while the inner server is (re)starting — up to 2 s.
    const inner: std.net.Stream = for (0..200) |_| {
        if (std.net.tcpConnectToAddress(inner_addr)) |s| break s else |_| std.Thread.sleep(10 * std.time.ns_per_ms);
    } else return error.ConnectionRefused;
    defer inner.close();
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

    try inner.writeAll(transformed.items);

    // Forward any body bytes already buffered by the http.Server reader.
    if (buffered_extra.len > 0) try inner.writeAll(buffered_extra);

    // Windows can report ERROR_INVALID_PARAMETER from ReadFile when combining
    // this shutdown-based bidirectional copy pattern with sockets. Use a
    // simpler one-way response copy there.
    if (builtin.os.tag == .windows) {
        copyStream(inner, client);
        return;
    }

    // Bidirectional pipe: remaining request body client→inner, response inner→client.
    // The inner→client thread shuts down the client write side when inner closes,
    // which unblocks the client→inner copy loop below.
    const fwd = std.Thread.spawn(.{}, copyStreamThenShutdown, .{ inner, client }) catch return;
    defer fwd.join();

    copyStream(client, inner);

    // Unblock the inner→client thread if client closed first.
    std.posix.shutdown(inner.handle, .recv) catch {};
}

/// Copy src→dst, then shut down the dst send side so the peer's read unblocks.
fn copyStreamThenShutdown(src: std.net.Stream, dst: std.net.Stream) void {
    copyStream(src, dst);
    std.posix.shutdown(dst.handle, .send) catch {};
}

fn copyStream(src: std.net.Stream, dst: std.net.Stream) void {
    var read_buf: [65536]u8 = undefined;
    var reader_state: [1024]u8 = undefined;
    var writer_state: [1024]u8 = undefined;
    var reader = src.reader(&reader_state);
    var writer = dst.writer(&writer_state);

    while (true) {
        const n = reader.interface().readSliceShort(&read_buf) catch return;
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

        const args = try IdeScheme.detect(ds.gpa, decoded_file, l, c);
        defer {
            for (args) |arg| ds.gpa.free(arg);
            ds.gpa.free(args);
        }

        if (args.len == 0) return;
        log.debug("opening in editor: {s}", .{args[0]});

        var child_proc = std.process.Child.init(args, ds.gpa);
        child_proc.stdin_behavior = .Ignore;
        child_proc.stdout_behavior = .Ignore;
        child_proc.stderr_behavior = .Ignore;

        child_proc.spawn() catch |err| {
            log.debug("editor failed to spawn: {s}", .{@errorName(err)});
            return;
        };
        _ = child_proc.wait() catch {};
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
