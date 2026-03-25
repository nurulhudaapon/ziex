/// DevServer - a lightweight proxy that owns the user-facing port so it never, this is based on WebServer.zig reom Zig std
/// drops during app binary restarts, and provides a stable WebSocket endpoint
/// for hot-reload signals and error overlays.
///
/// Architecture:
///   Browser ──HTTP──► DevServer (outer_port, stays alive)
///                         ├─ /.well-known/_zx/  → WebSocket and related assets (served here)
///                         └─ everything else    → proxy → app binary (inner_port)
///
/// WebSocket messages sent to browsers:
///   {"type":"connected"}              → handshake confirmation
///   {"type":"reload"}                 → app binary restarted, update page
///   {"type":"error","message":"..."}  → build failed, show error overlay
///   {"type":"clear"}                  → previous error resolved
///
/// On rebuild: dev.zig kills app binary → starts new one → calls notifyReload()
///             DevServer sends reload message to all WebSocket clients.
const std = @import("std");
const http = std.http;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.devserver);

const dev_script_src = @embedFile("devscript.js");

/// Minimal HTML shell served when the inner app is not running (e.g. initial
/// build errors). It includes the devscript so the browser can connect to the
/// DevServer WebSocket and display the error overlay immediately.
const ERROR_SHELL_HTML =
    "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">" ++
    "<title>ZX Dev</title><style>body{margin:0;background:#111;color:#aaa;font-family:system-ui,sans-serif;" ++
    "display:flex;align-items:center;justify-content:center;height:100vh}" ++
    ".c{text-align:center}.s{animation:_zx_spin 1.5s linear infinite;margin-bottom:16px}" ++
    "@keyframes _zx_spin{to{transform:rotate(360deg)}}</style></head>" ++
    "<body><div class=\"c\">" ++
    "<svg class=\"s\" width=\"32\" height=\"32\" viewBox=\"0 0 16 16\"><circle cx=\"8\" cy=\"8\" r=\"6\" fill=\"none\" stroke=\"#333\" stroke-width=\"2\"/>" ++
    "<path d=\"M8 2a6 6 0 0 1 6 6\" fill=\"none\" stroke=\"#3b82f6\" stroke-width=\"2\" stroke-linecap=\"round\"/></svg>" ++
    "<div>Waiting for build...</div></div>" ++
    "<script src=\"/.well-known/_zx/devscript.js\"></script></body></html>";

const DevServer = @This();

const EventType = enum { reload, @"error", clear, raw_json, building };

const QueuedEvent = struct {
    event_type: EventType,
    /// Owned payload for error/raw_json events; null otherwise.
    payload: ?[]u8,
};

const EVENT_QUEUE_CAP = 16;

gpa: Allocator,
/// User-facing address (what the browser connects to).
address: std.net.Address,
/// Port the app binary actually listens on (never exposed to users).
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

pub const Options = struct {
    gpa: Allocator,
    /// Address to bind the user-facing proxy to.
    address: std.net.Address,
    /// Port the app binary will listen on (must differ from address.getPort()).
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
        if (ds.event_queue[idx].payload) |p| ds.gpa.free(p);
        ds.event_tail +%= 1;
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

/// Push an event onto the queue and wake WS threads. Thread-safe.
fn pushEvent(ds: *DevServer, evt: EventType, payload: ?[]u8) void {
    ds.event_mutex.lock();
    const idx = ds.event_head % EVENT_QUEUE_CAP;
    // If queue is full, drop oldest event
    if (ds.event_head -% ds.event_tail >= EVENT_QUEUE_CAP) {
        const old_idx = ds.event_tail % EVENT_QUEUE_CAP;
        if (ds.event_queue[old_idx].payload) |p| ds.gpa.free(p);
        ds.event_tail +%= 1;
    }
    ds.event_queue[idx] = .{ .event_type = evt, .payload = payload };
    ds.event_head +%= 1;
    ds.event_mutex.unlock();
    _ = ds.update_id.rmw(.Add, 1, .release);
    std.Thread.Futex.wake(&ds.update_id, std.math.maxInt(u32));
}

/// Signal all connected WebSocket clients to reload. Thread-safe.
pub fn notifyReload(ds: *DevServer) void {
    ds.pushEvent(.reload, null);
}

/// Signal all connected WebSocket clients to show a build error overlay.
/// ANSI escape codes are stripped before sending. Thread-safe.
pub fn notifyError(ds: *DevServer, message: []const u8) void {
    const stripped = stripAnsi(ds.gpa, message) catch
        ds.gpa.dupe(u8, message) catch return;
    ds.pushEvent(.@"error", stripped);
}

/// Signal all connected WebSocket clients with a pre-built JSON payload. Thread-safe.
pub fn notifyRawJson(ds: *DevServer, json: []const u8) void {
    const owned = ds.gpa.dupe(u8, json) catch return;
    ds.pushEvent(.raw_json, owned);
}

/// Signal all connected WebSocket clients that a build is in progress. Thread-safe.
pub fn notifyBuilding(ds: *DevServer) void {
    ds.pushEvent(.building, null);
}

/// Signal all connected WebSocket clients to clear the error overlay. Thread-safe.
pub fn notifyClear(ds: *DevServer) void {
    ds.pushEvent(.clear, null);
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

    // 1. Intercept system requests (dev server only)
    if (std.mem.indexOf(u8, target, "/.well-known/_zx/")) |_| {
        if (std.mem.indexOf(u8, target, "devscript") != null) {
            log.debug("devscript matched: {s}", .{target});
            try req.respond(dev_script_src, .{
                .extra_headers = &.{
                    .{ .name = "Content-Type", .value = "application/javascript" },
                    .{ .name = "Cache-Control", .value = "no-cache" },
                    .{ .name = "Connection", .value = "close" },
                },
            });
            return;
        }

        if (std.mem.indexOf(u8, target, "open-in-editor") != null) {
            log.info("open-in-editor matched: {s}", .{target});
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

        // Unhandled dev route
        log.warn("unhandled dev route: {s}", .{target});
        try req.respond("not found", .{ .status = .not_found });
        return error.AlreadyReported;
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
    sock.writeMessage("{\"type\":\"connected\"}", .text) catch |err| {
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

    // Use 0 as sentinel so any event fired before this connection is replayed.
    // update_id starts at 0 and is only incremented by notify*, so a value > 0
    // means at least one event has been broadcast since the server started.
    var last_id: u32 = 0;
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
        const evt = ds.event_queue[event_index].event_type;
        const err_copy: ?[]u8 = if (ds.event_queue[event_index].payload) |p|
            ds.gpa.dupe(u8, p) catch null
        else
            null;
        ds.event_mutex.unlock();

        last_id +%= 1;

        log.debug("ws: broadcasting event: {s}", .{@tagName(evt)});
        switch (evt) {
            .reload => try sock.writeMessage("{\"type\":\"reload\"}", .text),
            .clear => try sock.writeMessage("{\"type\":\"clear\"}", .text),
            .building => try sock.writeMessage("{\"type\":\"building\"}", .text),
            .raw_json => {
                if (err_copy) |msg| {
                    defer ds.gpa.free(msg);
                    try sock.writeMessage(msg, .text);
                }
            },
            .@"error" => {
                if (err_copy) |msg| {
                    defer ds.gpa.free(msg);
                    var buf = std.ArrayList(u8).empty;
                    defer buf.deinit(ds.gpa);
                    try buf.appendSlice(ds.gpa, "{\"type\":\"error\",\"message\":\"");
                    try jsonEscape(ds.gpa, &buf, msg);
                    try buf.appendSlice(ds.gpa, "\"}");
                    try sock.writeMessage(buf.items, .text);
                }
            },
        }
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

/// JSON-escape a string and append to `list`.
fn jsonEscape(gpa: Allocator, list: *std.ArrayList(u8), s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try list.appendSlice(gpa, "\\\""),
            '\\' => try list.appendSlice(gpa, "\\\\"),
            '\n' => try list.appendSlice(gpa, "\\n"),
            '\r' => try list.appendSlice(gpa, "\\r"),
            '\t' => try list.appendSlice(gpa, "\\t"),
            0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F => {
                var tmp: [6]u8 = undefined;
                const encoded = try std.fmt.bufPrint(&tmp, "\\u{x:0>4}", .{c});
                try list.appendSlice(gpa, encoded);
            },
            else => try list.append(gpa, c),
        }
    }
}

/// Strip ANSI escape sequences from `input` and return a newly-allocated string.
fn stripAnsi(gpa: Allocator, input: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == 0x1B) {
            i += 1;
            if (i >= input.len) break;
            switch (input[i]) {
                '[' => {
                    // CSI sequence: skip to final byte (0x40–0x7E).
                    i += 1;
                    while (i < input.len and (input[i] < 0x40 or input[i] > 0x7E)) : (i += 1) {}
                    if (i < input.len) i += 1;
                },
                ']' => {
                    // OSC sequence: skip to BEL (0x07) or ST (ESC \).
                    i += 1;
                    while (i < input.len) : (i += 1) {
                        if (input[i] == 0x07) {
                            i += 1;
                            break;
                        }
                        if (input[i] == 0x1B and i + 1 < input.len and input[i + 1] == '\\') {
                            i += 2;
                            break;
                        }
                    }
                },
                else => i += 1,
            }
        } else {
            try out.append(gpa, input[i]);
            i += 1;
        }
    }
    return out.toOwnedSlice(gpa);
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
    var buf: [65536]u8 = undefined;
    while (true) {
        const n = src.read(&buf) catch return;
        if (n == 0) return;
        dst.writeAll(buf[0..n]) catch return;
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

        const args = try detectEditor(ds.gpa, decoded_file, l, c);
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

fn replaceAll(allocator: std.mem.Allocator, input: []const u8, pattern: []const u8, replacement: []const u8) ![]u8 {
    const size = std.mem.replacementSize(u8, input, pattern, replacement);
    const output = try allocator.alloc(u8, size);
    _ = std.mem.replace(u8, input, pattern, replacement, output);
    allocator.free(input); // free previous string (used for chained replacement)
    return output;
}

/// Detect editor and return command args to open file
fn detectEditor(allocator: std.mem.Allocator, file: []const u8, line: []const u8, col: []const u8) ![]const []const u8 {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    // 1. ZIEX_EDITOR override (e.g., "zed --open {file}:{line}:{col}")
    if (env_map.get("ZIEX_EDITOR")) |editor_cmd| {
        var args_list = std.ArrayList([]const u8).empty;
        var it = std.mem.tokenizeAny(u8, editor_cmd, " \t");
        while (it.next()) |token| {
            var arg = try allocator.dupe(u8, token);
            arg = try replaceAll(allocator, arg, "{file}", file);
            arg = try replaceAll(allocator, arg, "{line}", line);
            arg = try replaceAll(allocator, arg, "{col}", col);
            try args_list.append(allocator, arg);
        }
        if (args_list.items.len > 0) return try args_list.toOwnedSlice(allocator);
    }

    // 2. Auto-detect from environment using schema system
    for (EDITORS) |scheme| {
        if (scheme.match(env_map)) {
            return scheme.format(allocator, file, line, col);
        }
    }

    // Default to 'code' if nothing else matches
    var args = try allocator.alloc([]const u8, 3);
    args[0] = try allocator.dupe(u8, "code");
    args[1] = try allocator.dupe(u8, "-g");
    args[2] = try std.fmt.allocPrint(allocator, "{s}:{s}:{s}", .{ file, line, col });
    return args;
}

const CodeEditorScheme = struct {
    name: []const u8,
    args: []const []const u8,
    /// environment keys that must exist OR matches "KEY=VALUE" (value can have *)
    envs: []const []const u8,

    pub fn match(self: CodeEditorScheme, env_map: std.process.EnvMap) bool {
        if (self.envs.len == 0) return false;

        for (self.envs) |env_spec| {
            if (std.mem.indexOfScalar(u8, env_spec, '=')) |eq_idx| {
                const key = env_spec[0..eq_idx];
                const pattern = env_spec[eq_idx + 1 ..];
                const val = env_map.get(key) orelse return false;

                if (std.mem.startsWith(u8, pattern, "*") and std.mem.endsWith(u8, pattern, "*")) {
                    const inner = pattern[1 .. pattern.len - 1];
                    if (std.mem.indexOf(u8, val, inner) == null) return false;
                } else if (std.mem.startsWith(u8, pattern, "*")) {
                    const inner = pattern[1..];
                    if (!std.mem.endsWith(u8, val, inner)) return false;
                } else if (std.mem.endsWith(u8, pattern, "*")) {
                    const inner = pattern[0 .. pattern.len - 1];
                    if (!std.mem.startsWith(u8, val, inner)) return false;
                } else {
                    if (!std.mem.eql(u8, val, pattern)) return false;
                }
            } else {
                // Just check if key exists
                if (env_map.get(env_spec) == null) return false;
            }
        }
        return true;
    }

    pub fn format(self: CodeEditorScheme, allocator: std.mem.Allocator, file: []const u8, line: []const u8, col: []const u8) ![]const []const u8 {
        var args_list = std.ArrayList([]const u8).empty;

        for (self.args) |arg| {
            var new_arg = try allocator.dupe(u8, arg);
            new_arg = try replaceAll(allocator, new_arg, "{file}", file);
            new_arg = try replaceAll(allocator, new_arg, "{line}", line);
            new_arg = try replaceAll(allocator, new_arg, "{col}", col);
            try args_list.append(allocator, new_arg);
        }
        return args_list.toOwnedSlice(allocator);
    }
};

const EDITORS = [_]CodeEditorScheme{
    .{
        .name = "Antigravity",
        .args = &.{ "agy", "-g", "{file}:{line}:{col}" },
        .envs = &.{ "TERM_PROGRAM=vscode", "VSCODE_GIT_ASKPASS_NODE=*Antigravity*" },
    },
    .{
        .name = "Cursor",
        .args = &.{ "cursor", "-g", "{file}:{line}:{col}" },
        .envs = &.{ "TERM_PROGRAM=vscode", "VSCODE_GIT_ASKPASS_NODE=*Cursor*" },
    },
    .{
        .name = "VS Code",
        .args = &.{ "code", "-g", "{file}:{line}:{col}" },
        .envs = &.{"TERM_PROGRAM=vscode"},
    },
    .{
        .name = "Zed",
        .args = &.{ "zed", "{file}:{line}:{col}" },
        .envs = &.{"ZED_TERM"},
    },
    .{
        .name = "IntelliJ IDEA",
        .args = &.{ "idea", "--line", "{line}", "--column", "{col}", "{file}" },
        .envs = &.{"TERMINAL_EMULATOR=JetBrains*"},
    },
    .{
        .name = "Emacs",
        .args = &.{ "emacsclient", "-n", "+{line}:{col} {file}" },
        .envs = &.{"INSIDE_EMACS"},
    },
    .{
        .name = "Vim",
        .args = &.{ "vim", "+{line}", "{file}" },
        .envs = &.{"VIM"},
    },
    .{
        .name = "Vim (Runtime)",
        .args = &.{ "vim", "+{line}", "{file}" },
        .envs = &.{"VIMRUNTIME"},
    },
};
