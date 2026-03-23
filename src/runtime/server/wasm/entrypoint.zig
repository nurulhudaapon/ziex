const std = @import("std");
const zx = @import("../../../root.zig");
const kv = @import("kv.zig");
const render = @import("../../server/render.zig");
const server_dispatch = @import("../../server/dispatch.zig");
const ext = @import("extern.zig");
const zx_injections = @import("zx_injections");
const tree = @import("../../core/tree.zig");

const Router = zx.Router;
const Component = zx.Component;

fn injectZxInjections(allocator: std.mem.Allocator, page: *Component) void {
    if (zx_injections.head_starting.len > 0) {
        if (tree.getElementByName(page, allocator, .head)) |el|
            tree.prependChild(el, allocator, .{ .text = zx_injections.head_starting }) catch {};
    }
    if (zx_injections.head_ending.len > 0) {
        if (tree.getElementByName(page, allocator, .head)) |el|
            tree.appendChild(el, allocator, .{ .text = zx_injections.head_ending }) catch {};
    }
    if (zx_injections.body_starting.len > 0) {
        if (tree.getElementByName(page, allocator, .body)) |el|
            tree.prependChild(el, allocator, .{ .text = zx_injections.body_starting }) catch {};
    }
    if (zx_injections.body_ending.len > 0) {
        if (tree.getElementByName(page, allocator, .body)) |el|
            tree.appendChild(el, allocator, .{ .text = zx_injections.body_ending }) catch {};
    }
}

pub fn run() !void {
    kv.use();
    const allocator = std.heap.wasm_allocator;

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    var pathname: []const u8 = "/";
    var search: []const u8 = "";
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
                    .value = std.mem.trimLeft(u8, header_str[sep + 1 ..], " "),
                });
            }
        }
    }

    // --- Set up WASI backends --- //
    var wasi_headers = WasiHeaders{ .entries = header_entries.items };
    var wasi_search = WasiSearchParams{ .search = search };
    var wasi_res = WasiResponse.init(allocator);
    defer wasi_res.deinit();

    // --- Stdout/stderr writers --- //
    var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
    var stdout = &stdout_writer.interface;

    var stderr_writer = std.fs.File.stderr().writerStreaming(&.{});
    const stderr = &stderr_writer.interface;

    var stdin_body_buf: std.Io.Writer.Allocating = .init(allocator);
    defer stdin_body_buf.deinit();
    var stdin_read_buf: [4096]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().readerStreaming(&stdin_read_buf);
    _ = stdin_reader.interface.streamRemaining(&stdin_body_buf.writer) catch {};

    var wasi_req = WasiRequest{ .body = stdin_body_buf.written() };

    // Extract headers needed before request construction
    var content_type: []const u8 = "";
    var cookie_header: []const u8 = "";
    for (header_entries.items) |entry| {
        if (std.ascii.eqlIgnoreCase(entry.name, "content-type")) content_type = entry.value;
        if (std.ascii.eqlIgnoreCase(entry.name, "cookie")) cookie_header = entry.value;
    }
    var wasi_form_data = WasiFormData{
        .body = stdin_body_buf.written(),
        .content_type = content_type,
        .allocator = allocator,
    };
    var wasi_multi_form_data = WasiMultiFormData{
        .body = stdin_body_buf.written(),
        .content_type = content_type,
        .allocator = allocator,
    };

    const request = zx.server.Request{
        .url = "",
        .method = method,
        .pathname = pathname,
        .search = search,
        .headers = .{
            .backend_ctx = @ptrCast(&wasi_headers),
            .vtable = &WasiHeaders.vtable,
        },
        .searchParams = .{
            .backend_ctx = @ptrCast(&wasi_search),
            .vtable = &WasiSearchParams.vtable,
        },
        .arena = allocator,
        .backend_ctx = @ptrCast(&wasi_req),
        .vtable = &WasiRequest.vtable,
        .params = .{
            .backend_ctx = @ptrCast(&wasi_req),
            .vtable = &WasiRequest.params_vtable,
        },
        .cookies = .{ .header_value = cookie_header },
        .formdata_backend_ctx = @ptrCast(&wasi_form_data),
        .formdata_vtable = &WasiFormData.vtable,
        .multiformdata_backend_ctx = @ptrCast(&wasi_multi_form_data),
        .multiformdata_vtable = &WasiMultiFormData.vtable,
    };

    const response = zx.server.Response{
        .arena = allocator,
        .backend_ctx = @ptrCast(&wasi_res),
        .vtable = &WasiResponse.vtable,
        .headers = .{
            .backend_ctx = @ptrCast(&wasi_res),
            .vtable = &WasiResponse.headers_vtable,
        },
        .cookies = .{
            .backend_ctx = @ptrCast(&wasi_res),
            .vtable = &WasiResponse.vtable,
        },
    };

    // --- Route matching and unified proxy/handler/layout logic --- //
    const route_match = Router.matchRoute(pathname, .{ .match = .exact });
    wasi_req.route_match = route_match;
    const matched_route = if (route_match) |m| m.route else null;

    // Unified proxy chain execution (cascading + local proxy)
    const local_proxy = if (matched_route) |r| r.page_proxy orelse r.route_proxy else null;
    const proxy_result = Router.executeProxyChain(
        pathname,
        local_proxy,
        request,
        response,
        allocator,
    );
    if (proxy_result.aborted) {
        try sendResponse(stdout, stderr, &wasi_res);
        return;
    }

    if (matched_route) |route| {
        var pagectx = zx.PageContext{
            .request = request,
            .response = response,
            .allocator = allocator,
            .arena = allocator,
        };

        // --- Server Action Dispatch --- //
        switch (try server_dispatch.dispatchAction(request, response, allocator, allocator, route.path, pagectx, route.page)) {
            .not_triggered => {},
            .ok_native => {},
            .ok => |r| {
                if (r.body) |body| {
                    wasi_res.setContentTypeStr("application/json");
                    wasi_res.body.deinit();
                    wasi_res.body = .init(allocator);
                    wasi_res.body.writer.writeAll(body) catch {};
                }
                try sendResponse(stdout, stderr, &wasi_res);
                return;
            },
            .not_found => {
                wasi_res.status = 400;
                wasi_res.body.deinit();
                wasi_res.body = .init(allocator);
                wasi_res.body.writer.writeAll("No action handler registered for this route") catch {};
                try sendResponse(stdout, stderr, &wasi_res);
                return;
            },
            .page_error => {
                wasi_res.status = 500;
                try sendResponse(stdout, stderr, &wasi_res);
                return;
            },
        }

        // --- Server Event Dispatch --- //
        switch (try server_dispatch.dispatchServerEvent(request, allocator, allocator, route.path, pagectx, route.page)) {
            .not_triggered => {},
            .ok_native => {},
            .ok => |r| {
                wasi_res.setContentTypeStr("application/json");
                wasi_res.body.deinit();
                wasi_res.body = .init(allocator);
                wasi_res.body.writer.writeAll(r.body orelse "{}") catch {};
                try sendResponse(stdout, stderr, &wasi_res);
                return;
            },
            .not_found => {
                wasi_res.status = 404;
                wasi_res.body.deinit();
                wasi_res.body = .init(allocator);
                wasi_res.body.writer.writeAll("No server event handler registered for this route") catch {};
                try sendResponse(stdout, stderr, &wasi_res);
                return;
            },
            .page_error => {
                wasi_res.status = 500;
                try sendResponse(stdout, stderr, &wasi_res);
                return;
            },
        }

        // --- API route dispatch --- //
        if (route.route) |handlers| {
            if (Router.resolveCustomHandler(handlers, method, null)) |handler_fn| {
                var wasi_socket = WasiSocket{};
                const socket: zx.Socket = if (handlers.socket != null) .{
                    .backend_ctx = @ptrCast(&wasi_socket),
                    .vtable = &WasiSocket.vtable,
                } else .{};

                var route_ctx = zx.RouteContext{
                    .request = request,
                    .response = response,
                    .socket = socket,
                    .allocator = allocator,
                    .arena = allocator,
                };
                route_ctx._state_ptr = proxy_result.state_ptr;
                handler_fn(route_ctx) catch |err| {
                    if (!wasi_socket.upgraded) {
                        wasi_res.status = 500;
                        if (Router.renderErrorComponent(allocator, request, response, pathname, err)) |cmp| {
                            wasi_res.body.deinit();
                            wasi_res.body = .init(allocator);
                            render.current_route_path = pathname;
                            cmp.render(&wasi_res.body.writer) catch {};
                        }
                    }
                };

                if (wasi_socket.upgraded) {
                    // WebSocket message loop — do not send HTTP response
                    const upgrade_data = wasi_socket.upgradeData();
                    if (handlers.socket_open) |open_fn| {
                        open_fn(socket, upgrade_data, allocator, allocator) catch {};
                    }

                    const recv_buf = allocator.alloc(u8, 65536) catch return;
                    defer allocator.free(recv_buf);

                    while (true) {
                        const n = ext.ws_recv(recv_buf.ptr, recv_buf.len);
                        if (n < 0) break; // connection closed
                        if (handlers.socket) |socket_fn| {
                            socket_fn(socket, recv_buf[0..@intCast(n)], .text, upgrade_data, allocator, allocator) catch {};
                        }
                    }

                    if (handlers.socket_close) |close_fn| {
                        close_fn(socket, upgrade_data, allocator);
                    }
                    return;
                }

                try sendResponse(stdout, stderr, &wasi_res);
                return;
            }
        }

        // --- Page route rendering --- //
        if (route.page) |page_fn| {
            pagectx._state_ptr = proxy_result.state_ptr;

            var layoutctx = zx.LayoutContext{
                .request = request,
                .response = response,
                .allocator = allocator,
                .arena = allocator,
            };
            layoutctx._state_ptr = proxy_result.state_ptr;

            var page_component = page_fn(pagectx) catch |err| {
                wasi_res.status = 500;
                if (Router.renderErrorComponent(allocator, request, response, pathname, err)) |cmp| {
                    wasi_res.body.deinit();
                    wasi_res.body = .init(allocator);
                    render.current_route_path = pathname;
                    cmp.render(&wasi_res.body.writer) catch {};
                }
                wasi_res.setContentTypeStr("text/html");
                try sendResponse(stdout, stderr, &wasi_res);
                return;
            };

            page_component = Router.applyLayouts(route, pathname, layoutctx, page_component);
            injectZxInjections(allocator, &page_component);

            wasi_res.setContentTypeStr("text/html");

            const streaming_enabled = if (route.page_opts) |opts| opts.streaming else false;
            if (streaming_enabled) {
                try wasi_res.header_entries.append(allocator, .{ .name = "content-encoding", .value = "identify" });

                // Write metadata to stderr first — the JS worker reads it to build the
                // Response headers before WASM finishes, enabling a streaming body.
                try writeEdgeMeta(stderr, &wasi_res, true);

                render.current_route_path = pathname;
                var shell_writer = std.Io.Writer.Allocating.init(allocator);
                const async_components = render.stream(page_component, allocator, &shell_writer.writer) catch {
                    // Fallback: render the whole page at once.
                    var aw = std.Io.Writer.Allocating.init(allocator);
                    page_component.render(&aw.writer) catch {};
                    render.current_route_path = null;
                    try stdout.writeAll("<!DOCTYPE html>");
                    try stdout.writeAll(aw.written());
                    try stdout.flush();
                    return;
                };
                render.current_route_path = null;

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
            render.current_route_path = pathname;
            page_component.render(&aw.writer) catch {};
            render.current_route_path = null;

            try writeEdgeMeta(stderr, &wasi_res, false);
            try stdout.print("<!DOCTYPE html>{s}", .{aw.written()});
            try stdout.flush();
            return;
        }
    }

    // --- Not Found --- //
    wasi_res.status = 404;
    wasi_res.setContentTypeStr("text/html");

    if (Router.renderNotFoundComponent(allocator, request, response, pathname, matched_route)) |cmp| {
        var aw = std.Io.Writer.Allocating.init(allocator);
        defer aw.deinit();
        render.current_route_path = pathname;
        cmp.render(&aw.writer) catch {};

        try writeEdgeMeta(stderr, &wasi_res, false);
        try stdout.print("<!DOCTYPE html>{s}", .{aw.written()});
    } else {
        try writeEdgeMeta(stderr, &wasi_res, false);
        try stdout.print("404 Not Found", .{});
    }
    try stdout.flush();
}

/// Send response: write metadata to stderr, body to stdout
fn sendResponse(stdout: *std.Io.Writer, stderr: *std.Io.Writer, wasi_res: *WasiResponse) !void {
    try writeEdgeMeta(stderr, wasi_res, false);
    const body = wasi_res.written();
    if (body.len > 0) try stdout.print("{s}", .{body});
    try stdout.flush();
}

/// Write edge response metadata as a JSON line to stderr.
fn writeEdgeMeta(stderr: *std.Io.Writer, res: *const WasiResponse, streaming: bool) !void {
    try stderr.print("__EDGE_META__:{{\"status\":{d}", .{res.status});
    if (streaming) try stderr.print(",\"streaming\":true", .{});
    if (res.header_entries.items.len > 0) {
        try stderr.print(",\"headers\":[", .{});
        for (res.header_entries.items, 0..) |entry, i| {
            if (i > 0) try stderr.print(",", .{});
            try stderr.print("[\"{s}\",\"{s}\"]", .{ entry.name, entry.value });
        }
        try stderr.print("]", .{});
    }
    try stderr.print("}}\n", .{});
    try stderr.flush();
}

// -- Net WASI Adapters -- //
const HeaderEntry = struct { name: []const u8, value: []const u8 };

/// WASI request headers backend - reads from CLI --header args
const WasiHeaders = struct {
    entries: []const HeaderEntry,

    const vtable = zx.server.Request.Headers.HeadersVTable{
        .get = &get,
        .has = &has,
    };

    fn get(ctx: *anyopaque, name: []const u8) ?[]const u8 {
        const self: *WasiHeaders = @ptrCast(@alignCast(ctx));
        for (self.entries) |entry| {
            if (std.ascii.eqlIgnoreCase(entry.name, name)) return entry.value;
        }
        return null;
    }

    fn has(ctx: *anyopaque, name: []const u8) bool {
        return get(ctx, name) != null;
    }
};

/// WASI URL search params backend - parses query string
const WasiSearchParams = struct {
    search: []const u8,

    const vtable = zx.server.Request.URLSearchParams.URLSearchParamsVTable{
        .get = &get,
        .has = &has,
    };

    fn get(ctx: *anyopaque, name: []const u8) ?[]const u8 {
        const self: *WasiSearchParams = @ptrCast(@alignCast(ctx));
        const query = if (self.search.len > 0 and self.search[0] == '?') self.search[1..] else self.search;
        var iter = std.mem.splitScalar(u8, query, '&');
        while (iter.next()) |pair| {
            if (pair.len == 0) continue;
            if (std.mem.indexOfScalar(u8, pair, '=')) |eq| {
                if (std.mem.eql(u8, pair[0..eq], name)) return pair[eq + 1 ..];
            } else {
                if (std.mem.eql(u8, pair, name)) return "";
            }
        }
        return null;
    }

    fn has(ctx: *anyopaque, name: []const u8) bool {
        return get(ctx, name) != null;
    }
};

/// WASI request backend - provides access to the request body read from stdin
const WasiRequest = struct {
    body: []const u8,
    route_match: ?Router.RouteMatch = null,

    const vtable = zx.server.Request.VTable{
        .text = &text,
    };

    const params_vtable = zx.server.Request.Params.ParamsVTable{
        .getParam = &getParam,
    };

    fn text(ctx: *anyopaque) ?[]const u8 {
        const self: *WasiRequest = @ptrCast(@alignCast(ctx));
        if (self.body.len == 0) return null;
        return self.body;
    }

    fn getParam(ctx: *anyopaque, name: []const u8) ?[]const u8 {
        const self: *WasiRequest = @ptrCast(@alignCast(ctx));
        const m = self.route_match orelse return null;
        return m.getParam(name);
    }
};

/// WASI form data backend - lazily parses application/x-www-form-urlencoded body
const WasiFormData = struct {
    body: []const u8,
    content_type: []const u8,
    allocator: std.mem.Allocator,

    keys: [32][]const u8 = undefined,
    values: [32][]const u8 = undefined,
    count: usize = 0,
    parsed: bool = false,

    const vtable = zx.server.Request.FormDataVTable{
        .get = &get,
        .has = &has,
        .entries = &entries,
    };

    fn parse(self: *WasiFormData) void {
        if (self.parsed) return;
        self.parsed = true;
        self.count = 0;

        // Only handle application/x-www-form-urlencoded
        const ct = self.content_type;
        const prefix = "application/x-www-form-urlencoded";
        const is_urlencoded = ct.len >= prefix.len and std.ascii.eqlIgnoreCase(ct[0..prefix.len], prefix);
        if (!is_urlencoded) return;

        var iter = std.mem.splitScalar(u8, self.body, '&');
        while (iter.next()) |pair| {
            if (pair.len == 0) continue;
            if (self.count >= self.keys.len) break;
            const i = self.count;
            if (std.mem.indexOfScalar(u8, pair, '=')) |eq| {
                self.keys[i] = urlDecode(self.allocator, pair[0..eq]) catch pair[0..eq];
                self.values[i] = urlDecode(self.allocator, pair[eq + 1 ..]) catch pair[eq + 1 ..];
            } else {
                self.keys[i] = urlDecode(self.allocator, pair) catch pair;
                self.values[i] = "";
            }
            self.count += 1;
        }
    }

    fn get(ctx: *anyopaque, name: []const u8) ?[]const u8 {
        const self: *WasiFormData = @ptrCast(@alignCast(ctx));
        self.parse();
        for (self.keys[0..self.count], 0..) |key, i| {
            if (std.mem.eql(u8, key, name)) return self.values[i];
        }
        return null;
    }

    fn has(ctx: *anyopaque, name: []const u8) bool {
        return get(ctx, name) != null;
    }

    fn entries(ctx: *anyopaque) ?zx.server.Request.FormData.Iterator {
        const self: *WasiFormData = @ptrCast(@alignCast(ctx));
        self.parse();
        return .{
            .keys = self.keys[0..self.count],
            .values = self.values[0..self.count],
        };
    }
};

/// WASI multipart/form-data backend - parses multipart body
const WasiMultiFormData = struct {
    body: []const u8,
    content_type: []const u8,
    allocator: std.mem.Allocator,

    keys: [32][]const u8 = undefined,
    values: [32]zx.server.Request.MultiFormData.Value = undefined,
    count: usize = 0,
    parsed: bool = false,

    const vtable = zx.server.Request.MultiFormDataVTable{
        .get = &get,
        .has = &has,
        .entries = &entries,
        .getAll = &getAll,
    };

    fn getBoundary(content_type: []const u8) ?[]const u8 {
        const needle = "boundary=";
        const idx = std.mem.indexOf(u8, content_type, needle) orelse return null;
        const rest = content_type[idx + needle.len ..];
        const end = std.mem.indexOfAny(u8, rest, "; \t\r\n") orelse rest.len;
        return if (end == 0) null else rest[0..end];
    }

    /// Extract a named parameter value from a header directive string.
    /// e.g. extractParam(`form-data; name="foo"; filename="bar"`, "name") -> "foo"
    fn extractParam(directive: []const u8, param: []const u8) ?[]const u8 {
        var i: usize = 0;
        while (i < directive.len) {
            while (i < directive.len and (directive[i] == ' ' or directive[i] == ';' or directive[i] == '\t')) i += 1;
            if (i >= directive.len) break;
            // Check param=
            if (i + param.len + 1 <= directive.len and
                std.ascii.eqlIgnoreCase(directive[i .. i + param.len], param) and
                directive[i + param.len] == '=')
            {
                i += param.len + 1;
                if (i >= directive.len) return "";
                if (directive[i] == '"') {
                    i += 1;
                    const start = i;
                    while (i < directive.len and directive[i] != '"') i += 1;
                    return directive[start..i];
                } else {
                    const start = i;
                    while (i < directive.len and directive[i] != ';' and directive[i] != ' ') i += 1;
                    return directive[start..i];
                }
            }
            // Skip to next semicolon
            while (i < directive.len and directive[i] != ';') i += 1;
        }
        return null;
    }

    fn parse(self: *WasiMultiFormData) void {
        if (self.parsed) return;
        self.parsed = true;
        self.count = 0;

        const boundary = getBoundary(self.content_type) orelse return;

        // Delimiter line is "--" + boundary
        var delim_buf: [256]u8 = undefined;
        if (boundary.len + 2 > delim_buf.len) return;
        delim_buf[0] = '-';
        delim_buf[1] = '-';
        @memcpy(delim_buf[2 .. boundary.len + 2], boundary);
        const delim = delim_buf[0 .. boundary.len + 2];

        const body = self.body;
        var pos: usize = 0;

        // Seek to first boundary
        const first = std.mem.indexOf(u8, body[pos..], delim) orelse return;
        pos += first + delim.len;
        if (pos < body.len and body[pos] == '\r') pos += 1;
        if (pos < body.len and body[pos] == '\n') pos += 1;

        while (pos < body.len and self.count < self.keys.len) {
            // Check for closing delimiter "--boundary--"
            if (pos + delim.len + 2 <= body.len and
                std.mem.eql(u8, body[pos .. pos + delim.len], delim) and
                body[pos + delim.len] == '-') break;

            // Parse part headers
            var name: ?[]const u8 = null;
            var filename: ?[]const u8 = null;

            while (pos < body.len) {
                const line_end = std.mem.indexOf(u8, body[pos..], "\r\n") orelse break;
                const line = body[pos .. pos + line_end];
                pos += line_end + 2;
                if (line.len == 0) break; // blank line ends headers

                const cd_prefix = "content-disposition:";
                if (line.len > cd_prefix.len and std.ascii.eqlIgnoreCase(line[0..cd_prefix.len], cd_prefix)) {
                    const rest = std.mem.trimLeft(u8, line[cd_prefix.len..], " \t");
                    if (extractParam(rest, "name")) |n| name = n;
                    if (extractParam(rest, "filename")) |f| filename = f;
                }
            }

            // Find end of part body (next delimiter, preceded by \r\n)
            const part_end = std.mem.indexOf(u8, body[pos..], delim) orelse break;
            var part_body = body[pos .. pos + part_end];
            // Strip trailing CRLF that belongs to the boundary
            if (part_body.len >= 2 and part_body[part_body.len - 2] == '\r' and part_body[part_body.len - 1] == '\n') {
                part_body = part_body[0 .. part_body.len - 2];
            }
            pos += part_end + delim.len;
            if (pos < body.len and body[pos] == '\r') pos += 1;
            if (pos < body.len and body[pos] == '\n') pos += 1;

            if (name) |n| {
                const i = self.count;
                self.keys[i] = n;
                self.values[i] = .{ .data = part_body, .filename = filename };
                self.count += 1;
            }
        }
    }

    fn get(ctx: *anyopaque, name: []const u8) ?zx.server.Request.MultiFormData.Value {
        const self: *WasiMultiFormData = @ptrCast(@alignCast(ctx));
        self.parse();
        for (self.keys[0..self.count], 0..) |key, i| {
            if (std.mem.eql(u8, key, name)) return self.values[i];
        }
        return null;
    }

    fn has(ctx: *anyopaque, name: []const u8) bool {
        return get(ctx, name) != null;
    }

    fn getAll(ctx: *anyopaque, name: []const u8, allocator: std.mem.Allocator) ?[]const zx.server.Request.MultiFormData.Value {
        const self: *WasiMultiFormData = @ptrCast(@alignCast(ctx));
        self.parse();
        var count: usize = 0;
        for (self.keys[0..self.count]) |key| {
            if (std.mem.eql(u8, key, name)) count += 1;
        }
        if (count == 0) return null;
        const result = allocator.alloc(zx.server.Request.MultiFormData.Value, count) catch return null;
        var idx: usize = 0;
        for (self.keys[0..self.count], 0..) |key, i| {
            if (std.mem.eql(u8, key, name)) {
                result[idx] = self.values[i];
                idx += 1;
            }
        }
        return result;
    }

    fn entries(ctx: *anyopaque) ?zx.server.Request.MultiFormData.Iterator {
        const self: *WasiMultiFormData = @ptrCast(@alignCast(ctx));
        self.parse();
        return .{
            .keys = self.keys[0..self.count],
            .values = self.values[0..self.count],
        };
    }
};

/// Decode a URL-encoded string (%xx and + → space). Returns allocated slice.
fn urlDecode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var buf = try allocator.alloc(u8, input.len);
    var out: usize = 0;
    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '+') {
            buf[out] = ' ';
            out += 1;
            i += 1;
        } else if (input[i] == '%' and i + 2 < input.len) {
            const hi = std.fmt.charToDigit(input[i + 1], 16) catch null;
            const lo = std.fmt.charToDigit(input[i + 2], 16) catch null;
            if (hi != null and lo != null) {
                buf[out] = (hi.? << 4) | lo.?;
                out += 1;
                i += 3;
            } else {
                buf[out] = input[i];
                out += 1;
                i += 1;
            }
        } else {
            buf[out] = input[i];
            out += 1;
            i += 1;
        }
    }
    return buf[0..out];
}

/// WASI response backend - stores response data in memory for later output
const WasiResponse = struct {
    status: u16 = 200,
    body: std.Io.Writer.Allocating,
    header_entries: std.ArrayList(HeaderEntry),
    allocator: std.mem.Allocator,

    const vtable = zx.server.Response.VTable{
        .setStatus = &setStatus,
        .setBody = &setBody,
        .setHeader = &setHeader,
        .getWriter = &getWriter,
        .writeChunk = &writeChunk,
        .clearWriter = &clearWriter,
        .setCookie = &setCookie,
    };

    const headers_vtable = zx.server.Response.Headers.HeadersVTable{
        .get = &getHeader,
        .set = &setHeader,
        .add = &addHeader,
    };

    fn init(alloc: std.mem.Allocator) WasiResponse {
        return .{
            .allocator = alloc,
            .body = .init(alloc),
            .header_entries = .empty,
        };
    }

    fn deinit(self: *WasiResponse) void {
        self.body.deinit();
        self.header_entries.deinit(self.allocator);
    }

    fn written(self: *WasiResponse) []const u8 {
        return self.body.written();
    }

    fn setContentTypeStr(self: *WasiResponse, ct: []const u8) void {
        for (self.header_entries.items) |*entry| {
            if (std.ascii.eqlIgnoreCase(entry.name, "Content-Type")) {
                entry.value = ct;
                return;
            }
        }
        self.header_entries.append(self.allocator, .{ .name = "Content-Type", .value = ct }) catch {};
    }

    fn setStatus(ctx: *anyopaque, code: u16) void {
        const self: *WasiResponse = @ptrCast(@alignCast(ctx));
        self.status = code;
    }

    fn setBody(ctx: *anyopaque, content: []const u8) void {
        const self: *WasiResponse = @ptrCast(@alignCast(ctx));
        self.body.deinit();
        self.body = .init(self.allocator);
        self.body.writer.writeAll(content) catch {};
    }

    fn setHeader(ctx: *anyopaque, name: []const u8, value: []const u8) void {
        const self: *WasiResponse = @ptrCast(@alignCast(ctx));
        for (self.header_entries.items) |*entry| {
            if (std.ascii.eqlIgnoreCase(entry.name, name)) {
                entry.value = value;
                return;
            }
        }
        self.header_entries.append(self.allocator, .{ .name = name, .value = value }) catch {};
    }

    fn getHeader(ctx: *anyopaque, name: []const u8) ?[]const u8 {
        const self: *WasiResponse = @ptrCast(@alignCast(ctx));
        for (self.header_entries.items) |entry| {
            if (std.ascii.eqlIgnoreCase(entry.name, name)) return entry.value;
        }
        return null;
    }

    fn addHeader(ctx: *anyopaque, name: []const u8, value: []const u8) void {
        const self: *WasiResponse = @ptrCast(@alignCast(ctx));
        self.header_entries.append(self.allocator, .{ .name = name, .value = value }) catch {};
    }

    fn getWriter(ctx: *anyopaque) *std.Io.Writer {
        const self: *WasiResponse = @ptrCast(@alignCast(ctx));
        return &self.body.writer;
    }

    fn writeChunk(ctx: *anyopaque, data: []const u8) anyerror!void {
        const self: *WasiResponse = @ptrCast(@alignCast(ctx));
        try self.body.writer.writeAll(data);
    }

    fn clearWriter(ctx: *anyopaque) void {
        const self: *WasiResponse = @ptrCast(@alignCast(ctx));
        self.body.deinit();
        self.body = .init(self.allocator);
    }

    fn setCookie(ctx: *anyopaque, name: []const u8, value: []const u8, opts: zx.server.Response.CookieOptions) anyerror!void {
        const self: *WasiResponse = @ptrCast(@alignCast(ctx));

        var buf = std.Io.Writer.Allocating.init(self.allocator);
        defer buf.deinit();

        try buf.writer.print("{s}={s}", .{ name, value });
        if (opts.path.len > 0) try buf.writer.print("; Path={s}", .{opts.path});
        if (opts.domain.len > 0) try buf.writer.print("; Domain={s}", .{opts.domain});
        if (opts.max_age) |max_age| try buf.writer.print("; Max-Age={d}", .{max_age});
        if (opts.secure) try buf.writer.writeAll("; Secure");
        if (opts.http_only) try buf.writer.writeAll("; HttpOnly");
        if (opts.same_site) |ss| try buf.writer.print("; SameSite={s}", .{switch (ss) {
            .lax => "Lax",
            .strict => "Strict",
            .none => "None",
        }});
        if (opts.partitioned) try buf.writer.writeAll("; Partitioned");

        const cookie_str = try self.allocator.dupe(u8, buf.written());
        try self.header_entries.append(self.allocator, .{ .name = "Set-Cookie", .value = cookie_str });
    }
};

/// std.log-compatible logFn for the edge (WASI) target.
/// Plug into std_options to route all std.log.* calls through the JS console
/// instead of writing formatted text to stderr.
pub fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const level: u8 = switch (message_level) {
        .err => 0,
        .warn => 1,
        .info => 2,
        .debug => 3,
    };
    const prefix = if (scope == .default) "" else "(" ++ @tagName(scope) ++ ") ";
    const msg = std.fmt.allocPrint(std.heap.wasm_allocator, prefix ++ format, args) catch return;
    defer std.heap.wasm_allocator.free(msg);
    ext._log(level, msg.ptr, msg.len);
}

/// WASI Socket backend for the Cloudflare Worker edge environment.
const WasiSocket = struct {
    upgraded: bool = false,
    /// Raw bytes of the upgrade data struct passed via ctx.socket.upgrade(data).
    /// Fixed-size buffer avoids allocation; 256 bytes covers all current use cases.
    upgrade_data_buf: [256]u8 = undefined,
    upgrade_data_len: usize = 0,

    fn upgradeData(self: *const WasiSocket) ?[]const u8 {
        if (self.upgrade_data_len == 0) return null;
        return self.upgrade_data_buf[0..self.upgrade_data_len];
    }

    const vtable = zx.Socket.VTable{
        .upgrade = &upgradeFn,
        .upgradeWithData = &upgradeWithDataFn,
        .write = &writeFn,
        .read = &readFn,
        .close = &closeFn,
        .subscribe = &subscribeFn,
        .unsubscribe = &unsubscribeFn,
        .publish = &publishFn,
        .isSubscribed = &isSubscribedFn,
        .setPublishToSelf = &setPublishToSelfFn,
    };

    fn upgradeFn(ctx: *anyopaque) anyerror!void {
        const self: *WasiSocket = @ptrCast(@alignCast(ctx));
        self.upgraded = true;
        ext.ws_upgrade();
    }

    fn upgradeWithDataFn(ctx: *anyopaque, data: []const u8) anyerror!void {
        const self: *WasiSocket = @ptrCast(@alignCast(ctx));
        self.upgraded = true;
        const len = @min(data.len, self.upgrade_data_buf.len);
        @memcpy(self.upgrade_data_buf[0..len], data[0..len]);
        self.upgrade_data_len = len;
        ext.ws_upgrade();
    }

    fn writeFn(ctx: *anyopaque, data: []const u8) anyerror!void {
        _ = ctx;
        ext.ws_write(data.ptr, data.len);
    }

    fn readFn(ctx: *anyopaque) ?[]const u8 {
        _ = ctx;
        return null; // reads come via ws_recv in the message loop
    }

    fn closeFn(ctx: *anyopaque) void {
        _ = ctx;
        const reason: []const u8 = "";
        ext.ws_close(1000, reason.ptr, reason.len);
    }

    fn subscribeFn(ctx: *anyopaque, topic: []const u8) void {
        _ = ctx;
        ext.ws_subscribe(topic.ptr, topic.len);
    }
    fn unsubscribeFn(ctx: *anyopaque, topic: []const u8) void {
        _ = ctx;
        ext.ws_unsubscribe(topic.ptr, topic.len);
    }
    fn publishFn(ctx: *anyopaque, topic: []const u8, message: []const u8) usize {
        _ = ctx;
        return ext.ws_publish(topic.ptr, topic.len, message.ptr, message.len);
    }
    fn isSubscribedFn(ctx: *anyopaque, topic: []const u8) bool {
        _ = ctx;
        return ext.ws_is_subscribed(topic.ptr, topic.len) != 0;
    }
    fn setPublishToSelfFn(ctx: *anyopaque, value: bool) void {
        _ = ctx;
        _ = value;
    }
};
