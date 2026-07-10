const Wasm = @This();

const std = @import("std");
const app_opts = @import("app_opts");

const zx = @import("../../../root.zig");
const App = @import("../App.zig");
const ext = @import("../../server/wasm/extern.zig");
const core_handler = @import("../Handler.zig");
const render = @import("../../server/render.zig");

const Router = zx.Router;
const Backend = zx.Http.Wasm.Backend;
const HeaderEntry = zx.Http.Wasm.HeaderEntry;
const base_path = app_opts.app_base_path;

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

    const matched = if (backend.route_match) |m| m.route else null;
    const handlers = if (matched) |r| r.route else null;
    const socket: zx.Socket = if (handlers != null and handlers.?.socket != null)
        .{ ._internal = .{ .http = http, .attached = true } }
    else
        .{};

    // --- Shared dispatcher --- //
    const outcome = try Router.handle(.{
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

    switch (outcome) {
        .response_ready => try sendResponse(stdout, stderr, &backend),

        .component => |c| {
            var component = c.component;
            if (c.streaming) {
                try backend.resp_headers.append(allocator, .{ .name = "content-encoding", .value = "identify" });
                try writeEdgeMeta(stderr, &backend, true);

                var shell_writer = std.Io.Writer.Allocating.init(allocator);
                const async_components = Router.streamComponent(component, allocator, &shell_writer.writer, base_path) catch {
                    // Fallback: render the whole page at once.
                    var aw = std.Io.Writer.Allocating.init(allocator);
                    component.render(&aw.writer, .{ .base_path = base_path }) catch {};
                    try stdout.writeAll("<!DOCTYPE html>");
                    try stdout.writeAll(aw.written());
                    try stdout.flush();
                    return;
                };

                try stdout.writeAll("<!DOCTYPE html>");
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

            var aw = std.Io.Writer.Allocating.init(allocator);
            defer aw.deinit();
            component.render(&aw.writer, .{ .base_path = base_path }) catch {};

            try writeEdgeMeta(stderr, &backend, false);
            try stdout.print("<!DOCTYPE html>{s}", .{aw.written()});
            try stdout.flush();
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
            backend.status = 404;
            backend.setContentTypeStr("text/html");

            if (core_handler.renderNotFound(pathname, request, response, allocator, nf.matched_route)) |not_found_cmp| {
                var aw = std.Io.Writer.Allocating.init(allocator);
                defer aw.deinit();
                var cmp = not_found_cmp;
                cmp.render(&aw.writer, .{ .base_path = base_path }) catch {};

                try writeEdgeMeta(stderr, &backend, false);
                try stdout.print("<!DOCTYPE html>{s}", .{aw.written()});
            } else {
                try writeEdgeMeta(stderr, &backend, false);
                try stdout.print("404 Not Found", .{});
            }
            try stdout.flush();
        },
    }
}

fn sendResponse(stdout: *std.Io.Writer, stderr: *std.Io.Writer, backend: *Backend) !void {
    try writeEdgeMeta(stderr, backend, false);
    const body = backend.written();
    if (body.len > 0) try stdout.print("{s}", .{body});
    try stdout.flush();
}

fn writeEdgeMeta(stderr: *std.Io.Writer, backend: *const Backend, streaming: bool) !void {
    try stderr.print("__EDGE_META__:{{\"status\":{d}", .{backend.status});
    if (streaming) try stderr.print(",\"streaming\":true", .{});
    if (backend.resp_headers.items.len > 0) {
        try stderr.print(",\"headers\":[", .{});
        for (backend.resp_headers.items, 0..) |entry, i| {
            if (i > 0) try stderr.print(",", .{});
            try stderr.print("[\"{s}\",\"{s}\"]", .{ entry.name, entry.value });
        }
        try stderr.print("]", .{});
    }
    try stderr.print("}}\n", .{});
    try stderr.flush();
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
