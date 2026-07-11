const Wasm = @This();

const std = @import("std");
const app_opts = @import("app_opts");

const zx = @import("../../../root.zig");
const App = @import("../App.zig");
const AppConfig = @import("../AppConfig.zig");
const ext = @import("../../server/wasm/extern.zig");
const core_handler = @import("../Handler.zig");
const render = @import("../../server/render.zig");
const PageCache = @import("../../server/PageCache.zig");

const Router = zx.Router;
const Backend = zx.Http.Wasm.Backend;
const HeaderEntry = zx.Http.Wasm.HeaderEntry;
const base_path = app_opts.app_base_path;
const feat_cache = app_opts.feat_cache_server;

var g_inita: zx.Init = undefined;

pub fn app(inita: zx.Init) App {
    g_inita = inita;
    return .{ .userdata = null, .vtable = &vtable };
}

const vtable = App.VTable{
    .start = &vtStart,
    .stop = App.failing_vtable.stop,
    .deinit = App.failing_vtable.deinit,
    .info = App.failing_vtable.info,
};

fn vtStart(_: ?*anyopaque) anyerror!void {
    return run(g_inita);
}

pub fn run(process_init: std.process.Init) !void {
    const allocator = std.heap.wasm_allocator;

    var args = try process_init.minimal.args.iterateAllocator(allocator);
    defer args.deinit();

    var pathname: []const u8 = "/";
    var search: []const u8 = "";
    var url: []const u8 = "";
    var method: zx.server.Request.Method = .GET;
    var header_entries = std.ArrayList(HeaderEntry).empty;
    defer header_entries.deinit(allocator);

    // --- Parse CLI flags --- //
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--pathname")) {
            pathname = args.next() orelse return error.MissingPathname;
        } else if (std.mem.eql(u8, arg, "--search")) {
            search = args.next() orelse return error.MissingSearch;
        } else if (std.mem.eql(u8, arg, "--method")) {
            const method_str = args.next() orelse return error.MissingMethod;
            method = std.meta.stringToEnum(zx.server.Request.Method, method_str) orelse return error.InvalidMethod;
        } else if (std.mem.eql(u8, arg, "--header")) {
            const header_str = args.next() orelse return error.MissingHeader;
            if (std.mem.indexOfScalar(u8, header_str, ':')) |sep| {
                try header_entries.append(allocator, .{
                    .name = header_str[0..sep],
                    .value = std.mem.trimStart(u8, header_str[sep + 1 ..], " "),
                });
            }
        } else if (std.mem.eql(u8, arg, "--url")) {
            url = args.next() orelse return error.MissingUrl;
        }
    }

    // --- Stdout/stderr writers --- //
    var stdout_writer = std.Io.File.stdout().writerStreaming(process_init.io, &.{});
    var stdout = &stdout_writer.interface;

    var stderr_writer = std.Io.File.stderr().writerStreaming(process_init.io, &.{});
    const stderr = &stderr_writer.interface;

    // --- Read request body from stdin --- //
    var stdin_body_buf: std.Io.Writer.Allocating = .init(allocator);
    defer stdin_body_buf.deinit();
    var stdin_read_buf: [4096]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(process_init.io, &stdin_read_buf);
    _ = stdin_reader.interface.streamRemaining(&stdin_body_buf.writer) catch {};

    var content_type: []const u8 = "";
    var cookie_header: []const u8 = "";
    for (header_entries.items) |entry| {
        if (std.ascii.eqlIgnoreCase(entry.name, "content-type")) content_type = entry.value;
        if (std.ascii.eqlIgnoreCase(entry.name, "cookie")) cookie_header = entry.value;
    }

    // --- Unified WASI backend --- //
    var backend = Backend.init(allocator);
    defer backend.deinit();
    backend.headers = header_entries.items;
    backend.search = search;
    backend.body = stdin_body_buf.written();
    backend.content_type = content_type;
    backend.cookie_header = cookie_header;
    backend.route_match = Router.matchRoute(pathname, .{ .match = .exact });

    const request = backend.request(method, pathname, url);
    const response = backend.response();
    const http = backend.http();

    var page_cache: if (feat_cache) PageCache else void = if (feat_cache)
        try PageCache.initKv(process_init.io, allocator, zx.kv.scoped(.@"page-cache"), AppConfig.CacheConfig{})
    else
        {};
    defer if (feat_cache) page_cache.deinit();

    const cache_status = if (feat_cache) page_cache.tryServe(request, response) else PageCache.Status.disabled;
    if (cache_status == .hit) {
        try sendResponse(stdout, stderr, &backend);
        return;
    }

    const matched = if (backend.route_match) |m| m.route else null;
    const handlers = if (matched) |r| r.route else null;
    const socket: zx.Socket = if (handlers != null and handlers.?.socket != null)
        .{ ._internal = .{ .http = http, .attached = true } }
    else
        .{};

    // --- Shared dispatcher --- //
    const result = try Router.handle(.{
        .http = http,
        .request = request,
        .response = response,
        .pathname = pathname,
        .method = method,
        .allocator = allocator,
        .arena = allocator,
        .base_path = base_path,
        .app_ctx = null,
        .socket = socket,
    });

    switch (result.outcome) {
        .response_ready => {
            if (comptime feat_cache) {
                if (cache_status == .miss) storePageCache(&page_cache, request, response, &backend, backend.written());
            }
            try sendResponse(stdout, stderr, &backend);
        },

        .component => |c| {
            var component = c.component;
            if (c.streaming) {
                try backend.resp_headers.append(allocator, .{ .name = "content-encoding", .value = "identify" });
                try writeZiexMeta(stderr, &backend, true);

                var shell_writer = std.Io.Writer.Allocating.init(allocator);
                const async_components = Router.streamComponent(component, allocator, &shell_writer.writer, base_path) catch |stream_err| switch (stream_err) {
                    error.NotFound => {
                        try emitNotFoundPage(stdout, stderr, &backend, http, pathname, request, response, allocator, matched);
                        return;
                    },
                    else => {
                        // Fallback: render the whole page at once.
                        try emitComponentBuffered(stdout, stderr, &backend, &page_cache, cache_status, request, response, http, pathname, allocator, matched, &component);
                        return;
                    },
                };

                try stdout.writeAll("<!DOCTYPE html>\n");
                try stdout.writeAll(shell_writer.written());
                try stdout.flush();

                if (async_components.len > 0) {
                    try stdout.writeAll(render.streaming_bootstrap_script);
                    for (async_components) |async_comp| {
                        const script = async_comp.renderScript(allocator) catch continue;
                        try stdout.writeAll(script);
                        try stdout.flush();
                    }
                }
                return;
            }

            try emitComponentBuffered(stdout, stderr, &backend, &page_cache, cache_status, request, response, http, pathname, allocator, matched, &component);
        },

        .ws_upgraded => {
            const upgrade_data = backend.upgradeData();
            if (handlers.?.socket_open) |open_fn| {
                open_fn(socket, upgrade_data, allocator, allocator) catch {};
            }

            const recv_buf = allocator.alloc(u8, 65536) catch return;
            defer allocator.free(recv_buf);

            while (true) {
                const n = ext.ws_recv(recv_buf.ptr, recv_buf.len);
                if (n < 0) break; // connection closed
                if (handlers.?.socket) |socket_fn| {
                    socket_fn(socket, recv_buf[0..@intCast(n)], .text, upgrade_data, allocator, allocator) catch {};
                }
            }

            if (handlers.?.socket_close) |close_fn| {
                close_fn(socket, upgrade_data, allocator);
            }
        },

        .not_found => |nf| {
            try emitHtmlOrPlain(stdout, stderr, &backend, nf.component);
        },
    }
}

fn emitComponentBuffered(
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    backend: *Backend,
    page_cache: anytype,
    cache_status: PageCache.Status,
    request: zx.server.Request,
    response: zx.server.Response,
    http: zx.Http,
    pathname: []const u8,
    allocator: std.mem.Allocator,
    matched_route: ?*const core_handler.Route,
    component: *zx.Component,
) !void {
    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();
    core_handler.renderHtmlDocument(&aw.writer, component, base_path) catch |err| switch (err) {
        error.NotFound => {
            try emitNotFoundPage(stdout, stderr, backend, http, pathname, request, response, allocator, matched_route);
            return;
        },
        else => {
            try emitErrorPage(stdout, stderr, backend, http, pathname, request, response, allocator, err);
            return;
        },
    };

    const body = aw.written();

    if (comptime feat_cache) {
        if (cache_status == .miss) {
            if (backend.resp_headers.items.len == 0 or !headerHas(backend.resp_headers.items, "Content-Type")) {
                backend.setContentTypeStr("text/html");
            }
            storePageCache(page_cache, request, response, backend, body);
        }
    }

    try writeZiexMeta(stderr, backend, false);
    try stdout.writeAll(body);
    try stdout.flush();
}

fn emitNotFoundPage(
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    backend: *Backend,
    http: zx.Http,
    pathname: []const u8,
    request: zx.server.Request,
    response: zx.server.Response,
    allocator: std.mem.Allocator,
    matched_route: ?*const core_handler.Route,
) !void {
    const component = core_handler.prepareNotFound(http, pathname, request, response, allocator, matched_route);
    try emitHtmlOrPlain(stdout, stderr, backend, component);
}

fn emitErrorPage(
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    backend: *Backend,
    http: zx.Http,
    pathname: []const u8,
    request: zx.server.Request,
    response: zx.server.Response,
    allocator: std.mem.Allocator,
    err: anyerror,
) !void {
    const component = core_handler.prepareError(http, pathname, request, response, allocator, err);
    try emitHtmlOrPlain(stdout, stderr, backend, component);
}

fn emitHtmlOrPlain(
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    backend: *Backend,
    component: ?zx.Component,
) !void {
    if (component) |cmp| {
        var aw = std.Io.Writer.Allocating.init(backend.allocator);
        defer aw.deinit();
        var page = cmp;
        core_handler.renderHtmlDocument(&aw.writer, &page, base_path) catch {};
        try writeZiexMeta(stderr, backend, false);
        try stdout.writeAll(aw.written());
    } else {
        try writeZiexMeta(stderr, backend, false);
        const body = backend.written();
        if (body.len > 0) try stdout.writeAll(body);
    }
    try stdout.flush();
}

fn storePageCache(
    page_cache: *PageCache,
    request: zx.server.Request,
    response: zx.server.Response,
    backend: *const Backend,
    body: []const u8,
) void {
    page_cache.store(request, response, .{
        .status = backend.status,
        .body = body,
        .content_type = headerGet(backend.resp_headers.items, "Content-Type") orelse "text/html",
    });
}

fn headerGet(headers: []const HeaderEntry, name: []const u8) ?[]const u8 {
    for (headers) |entry| {
        if (std.ascii.eqlIgnoreCase(entry.name, name)) return entry.value;
    }
    return null;
}

fn headerHas(headers: []const HeaderEntry, name: []const u8) bool {
    return headerGet(headers, name) != null;
}

fn sendResponse(stdout: *std.Io.Writer, stderr: *std.Io.Writer, backend: *Backend) !void {
    try writeZiexMeta(stderr, backend, false);
    const body = backend.written();
    if (body.len > 0) try stdout.print("{s}", .{body});
    try stdout.flush();
}

fn writeZiexMeta(stderr: *std.Io.Writer, backend: *const Backend, streaming: bool) !void {
    try stderr.print("__ZIEX_META__:{{\"status\":{d}", .{backend.status});
    if (streaming) try stderr.print(",\"streaming\":true", .{});
    if (backend.resp_headers.items.len > 0) {
        try stderr.print(",\"headers\":[", .{});
        for (backend.resp_headers.items, 0..) |entry, i| {
            if (i > 0) try stderr.print(",", .{});
            try stderr.writeAll("[");
            try writeJsonString(stderr, entry.name);
            try stderr.writeAll(",");
            try writeJsonString(stderr, entry.value);
            try stderr.writeAll("]");
        }
        try stderr.print("]", .{});
    }
    try stderr.print("}}\n", .{});
    try stderr.flush();
}

fn writeJsonString(writer: *std.Io.Writer, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try writer.print("\\u{x:0>4}", .{c});
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
    try writer.writeByte('"');
}

pub fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    log_args: anytype,
) void {
    const level: u8 = switch (message_level) {
        .err => 0,
        .warn => 1,
        .info => 2,
        .debug => 3,
    };
    const prefix = if (scope == .default) "" else "(" ++ @tagName(scope) ++ ") ";
    const msg = std.fmt.allocPrint(std.heap.wasm_allocator, prefix ++ format, log_args) catch return;
    defer std.heap.wasm_allocator.free(msg);
    ext._log(level, msg.ptr, msg.len);
}
