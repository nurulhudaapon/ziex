//! httpz backend adapter.
//! Creates abstract Request/Response from httpz types.
//!
//! This adapter converts between httpz-specific types and std.http types
//! used in the abstract Request/Response layer.

const std = @import("std");
const httpz = @import("httpz");
const Request = @import("../core/Request.zig");
const Response = @import("../core/Response.zig");
const Headers = @import("../core/Headers.zig");
const FormData = @import("../core/FormData.zig");
const MultiFormData = @import("../core/MultiFormData.zig");
const common = @import("../core/common.zig");

// --- Type Conversion Helpers --- //

/// Converts httpz.Method to std.http.Method.
/// Note: httpz has OTHER for unknown methods, std.http.Method doesn't.
/// OTHER is mapped to GET as a fallback (the original method string is preserved in method_str).
fn convertMethod(method: httpz.Method) std.http.Method {
    return switch (method) {
        .GET => .GET,
        .HEAD => .HEAD,
        .POST => .POST,
        .PUT => .PUT,
        .DELETE => .DELETE,
        .CONNECT => .CONNECT,
        .OPTIONS => .OPTIONS,
        .PATCH => .PATCH,
        // Default to CONNECT but the original method string is preserved in method_str
        .OTHER => .CONNECT, //TODO: figure out better way to handle this
    };
}

/// Converts httpz.Protocol to std.http.Version.
fn convertProtocol(protocol: httpz.Protocol) std.http.Version {
    return switch (protocol) {
        .HTTP10 => .@"HTTP/1.0",
        .HTTP11 => .@"HTTP/1.1",
    };
}

// --- Request Adapter --- //

/// Creates an abstract Request from an httpz.Request
pub fn createRequest(inner: *httpz.Request) Request {
    return (Request.Builder{
        .url = inner.url.raw,
        .method = convertMethod(inner.method),
        .method_str = inner.method_string,
        .pathname = inner.url.path,
        .referrer = inner.headers.get("referer") orelse "",
        .search = inner.url.query,
        .protocol = convertProtocol(inner.protocol),
        .arena = inner.arena,
        .userdata = @ptrCast(inner),
        .vtable = &request_vtable,
        .headers_userdata = @ptrCast(inner),
        .headers_vtable = &request_headers_vtable,
        .cookie_header = inner.headers.get("cookie") orelse "",
        .search_params_userdata = @ptrCast(inner),
        .search_params_vtable = &search_params_vtable,
        .params_userdata = @ptrCast(inner),
        .params_vtable = &params_vtable,
        .formdata_userdata = @ptrCast(inner),
        .formdata_vtable = &formdata_vtable,
        .multiformdata_userdata = @ptrCast(inner),
        .multiformdata_vtable = &multiformdata_vtable,
    }).build();
}

const request_vtable = Request.VTable{
    .text = &requestText,
};

const params_vtable = Request.Params.ParamsVTable{
    .getParam = &requestGetParam,
};

fn requestText(ctx: *anyopaque) ?[]const u8 {
    const req: *httpz.Request = @ptrCast(@alignCast(ctx));
    return req.body();
}

fn requestGetParam(ctx: *anyopaque, name: []const u8) ?[]const u8 {
    const req: *httpz.Request = @ptrCast(@alignCast(ctx));
    return req.param(name);
}

const request_headers_vtable = Request.Headers.HeadersVTable{
    .get = &requestHeadersGet,
    .has = &requestHeadersHas,
};

fn requestHeadersGet(ctx: *anyopaque, name: []const u8) ?[]const u8 {
    const req: *httpz.Request = @ptrCast(@alignCast(ctx));
    return req.headers.get(name);
}

fn requestHeadersHas(ctx: *anyopaque, name: []const u8) bool {
    const req: *httpz.Request = @ptrCast(@alignCast(ctx));
    return req.headers.has(name);
}

const search_params_vtable = Request.URLSearchParams.URLSearchParamsVTable{
    .get = &searchParamsGet,
    .has = &searchParamsHas,
};

fn searchParamsGet(ctx: *anyopaque, name: []const u8) ?[]const u8 {
    const req: *httpz.Request = @ptrCast(@alignCast(ctx));
    const query = req.query() catch return null;
    return query.get(name);
}

fn searchParamsHas(ctx: *anyopaque, name: []const u8) bool {
    const req: *httpz.Request = @ptrCast(@alignCast(ctx));
    const query = req.query() catch return false;
    return query.has(name);
}

// --- FormData Adapter (for application/x-www-form-urlencoded) --- //

const formdata_vtable = Request.FormDataVTable{
    .get = &formDataGet,
    .has = &formDataHas,
    .entries = &formDataEntries,
};

fn formDataGet(ctx: *anyopaque, name: []const u8) ?[]const u8 {
    const req: *httpz.Request = @ptrCast(@alignCast(ctx));

    // Only handle URL-encoded form data (application/x-www-form-urlencoded)
    if (req.formData()) |fd| {
        return fd.get(name);
    } else |_| {}

    return null;
}

fn formDataHas(ctx: *anyopaque, name: []const u8) bool {
    const req: *httpz.Request = @ptrCast(@alignCast(ctx));

    if (req.formData()) |fd| {
        return fd.has(name);
    } else |_| {}

    return false;
}

fn formDataEntries(ctx: *anyopaque) ?FormData.Iterator {
    const req: *httpz.Request = @ptrCast(@alignCast(ctx));
    _ = req;
    // Note: Iteration requires storing state which is complex via vtable
    // For now, return null - iteration not fully supported via adapter
    return null;
}

// --- MultiFormData Adapter (for multipart/form-data with file uploads) --- //

const multiformdata_vtable = Request.MultiFormDataVTable{
    .get = &multiFormDataGet,
    .has = &multiFormDataHas,
    .entries = &multiFormDataEntries,
};

fn multiFormDataGet(ctx: *anyopaque, name: []const u8) ?MultiFormData.Value {
    const req: *httpz.Request = @ptrCast(@alignCast(ctx));

    // Handle multipart form data (multipart/form-data)
    if (req.multiFormData()) |mfd| {
        if (mfd.get(name)) |entry| {
            return MultiFormData.Value{
                .data = entry.value,
                .filename = entry.filename,
            };
        }
    } else |_| {}

    return null;
}

fn multiFormDataHas(ctx: *anyopaque, name: []const u8) bool {
    const req: *httpz.Request = @ptrCast(@alignCast(ctx));

    if (req.multiFormData()) |mfd| {
        return mfd.has(name);
    } else |_| {}

    return false;
}

fn multiFormDataEntries(ctx: *anyopaque) ?MultiFormData.Iterator {
    const req: *httpz.Request = @ptrCast(@alignCast(ctx));
    _ = req;
    // Note: Iteration requires storing state which is complex via vtable
    // For now, return null - iteration not fully supported via adapter
    return null;
}

// --- Response Adapter --- //

/// Creates an abstract Response from an httpz.Response
pub fn createResponse(inner: *httpz.Response, arena: std.mem.Allocator) Response {
    return (Response.Builder{
        .status = inner.status,
        .arena = arena,
        .userdata = @ptrCast(inner),
        .vtable = &response_vtable,
        .headers_userdata = @ptrCast(inner),
        .headers_vtable = &response_headers_vtable,
    }).build();
}

const response_vtable = Response.VTable{
    .setStatus = &responseSetStatus,
    .setBody = &responseSetBody,
    .setHeader = &responseSetHeader,
    .getWriter = &responseGetWriter,
    .writeChunk = &responseWriteChunk,
    .clearWriter = &responseClearWriter,
    .setCookie = &responseSetCookie,
};

fn responseSetStatus(ctx: *anyopaque, status: u16) void {
    const res: *httpz.Response = @ptrCast(@alignCast(ctx));
    res.status = status;
}

fn responseSetBody(ctx: *anyopaque, content: []const u8) void {
    const res: *httpz.Response = @ptrCast(@alignCast(ctx));
    res.body = content;
}

fn responseSetHeader(ctx: *anyopaque, name: []const u8, value: []const u8) void {
    const res: *httpz.Response = @ptrCast(@alignCast(ctx));
    res.header(name, value);
}

fn responseGetWriter(ctx: *anyopaque) *std.Io.Writer {
    const res: *httpz.Response = @ptrCast(@alignCast(ctx));
    return res.writer();
}

fn httpzWriteFn(context: *const anyopaque, buffer: []const u8) anyerror!usize {
    const res: *httpz.Response = @ptrCast(@alignCast(@constCast(context)));
    res.writer().writeAll(buffer) catch |err| return err;
    return buffer.len;
}

fn responseWriteChunk(ctx: *anyopaque, data: []const u8) anyerror!void {
    const res: *httpz.Response = @ptrCast(@alignCast(ctx));
    try res.chunk(data);
}

fn responseClearWriter(ctx: *anyopaque) void {
    const res: *httpz.Response = @ptrCast(@alignCast(ctx));
    res.clearWriter();
}

fn responseSetCookie(ctx: *anyopaque, name: []const u8, value: []const u8, opts: common.CookieOptions) anyerror!void {
    const res: *httpz.Response = @ptrCast(@alignCast(ctx));
    // Convert from common.CookieOptions to httpz.CookieOpts
    const httpz_opts: httpz.response.CookieOpts = .{
        .path = opts.path,
        .domain = opts.domain,
        .max_age = opts.max_age,
        .secure = opts.secure,
        .http_only = opts.http_only,
        .partitioned = opts.partitioned,
        .same_site = if (opts.same_site) |ss| switch (ss) {
            .lax => .lax,
            .strict => .strict,
            .none => .none,
        } else null,
    };
    try res.setCookie(name, value, httpz_opts);
}

const response_headers_vtable = Response.Headers.HeadersVTable{
    .get = &responseHeadersGet,
    .set = &responseHeadersSet,
    .add = &responseHeadersAdd,
};

fn responseHeadersGet(ctx: *anyopaque, name: []const u8) ?[]const u8 {
    const res: *httpz.Response = @ptrCast(@alignCast(ctx));
    return res.headers.get(name);
}

fn responseHeadersSet(ctx: *anyopaque, name: []const u8, value: []const u8) void {
    const res: *httpz.Response = @ptrCast(@alignCast(ctx));
    res.header(name, value);
}

fn responseHeadersAdd(ctx: *anyopaque, name: []const u8, value: []const u8) void {
    const res: *httpz.Response = @ptrCast(@alignCast(ctx));
    res.headers.add(name, value);
}

// --- Headers Adapter (standalone, for use with both request/response) --- //

pub fn createRequestHeaders(inner: *httpz.Request) Headers {
    return (Headers.Builder{
        .backend_ctx = @ptrCast(inner),
        .vtable = &headers_request_vtable,
        .read_only = true,
    }).build();
}

pub fn createResponseHeaders(inner: *httpz.Response) Headers {
    return (Headers.Builder{
        .backend_ctx = @ptrCast(inner),
        .vtable = &headers_response_vtable,
        .read_only = false,
    }).build();
}

const headers_request_vtable = Headers.VTable{
    .get = &headersRequestGet,
    .has = &headersRequestHas,
    .set = &headersNoOpSet,
    .append = &headersNoOpAppend,
    .iterate = &headersRequestIterate,
};

const headers_response_vtable = Headers.VTable{
    .get = &headersResponseGet,
    .has = &headersResponseHas,
    .set = &headersResponseSet,
    .append = &headersResponseAppend,
    .iterate = &headersResponseIterate,
};

fn headersRequestGet(ctx: *anyopaque, name: []const u8) ?[]const u8 {
    const req: *httpz.Request = @ptrCast(@alignCast(ctx));
    return req.headers.get(name);
}

fn headersRequestHas(ctx: *anyopaque, name: []const u8) bool {
    const req: *httpz.Request = @ptrCast(@alignCast(ctx));
    return req.headers.has(name);
}

fn headersNoOpSet(_: *anyopaque, _: []const u8, _: []const u8) void {}
fn headersNoOpAppend(_: *anyopaque, _: []const u8, _: []const u8) void {}

fn headersRequestIterate(ctx: *anyopaque) ?Headers.Iterator {
    const req: *httpz.Request = @ptrCast(@alignCast(ctx));
    _ = req;
    // Note: Would need to store iterator state somewhere accessible
    // For now, return null - iteration not supported via vtable
    return null;
}

fn headersResponseGet(ctx: *anyopaque, name: []const u8) ?[]const u8 {
    const res: *httpz.Response = @ptrCast(@alignCast(ctx));
    return res.headers.get(name);
}

fn headersResponseHas(ctx: *anyopaque, name: []const u8) bool {
    const res: *httpz.Response = @ptrCast(@alignCast(ctx));
    return res.headers.has(name);
}

fn headersResponseSet(ctx: *anyopaque, name: []const u8, value: []const u8) void {
    const res: *httpz.Response = @ptrCast(@alignCast(ctx));
    res.header(name, value);
}

fn headersResponseAppend(ctx: *anyopaque, name: []const u8, value: []const u8) void {
    const res: *httpz.Response = @ptrCast(@alignCast(ctx));
    res.headers.add(name, value);
}

fn headersResponseIterate(ctx: *anyopaque) ?Headers.Iterator {
    const res: *httpz.Response = @ptrCast(@alignCast(ctx));
    _ = res;
    // Note: Would need to store iterator state somewhere accessible
    // For now, return null - iteration not supported via vtable
    return null;
}

// --- Utility: Get underlying httpz types (for code that still needs them) --- //

/// Get the underlying httpz.Request from an abstract Request
pub fn getHttpzRequest(request: *const Request) ?*httpz.Request {
    if (request._internal.userdata.request) |ctx| {
        return @ptrCast(@alignCast(ctx));
    }
    return null;
}

/// Get the underlying httpz.Response from an abstract Response
pub fn getHttpzResponse(response: *const Response) ?*httpz.Response {
    if (response._internal.userdata) |ctx| {
        return @ptrCast(@alignCast(ctx));
    }
    return null;
}

// --- Socket Adapter --- //

const routing = @import("../core/routing.zig");
const Socket = routing.Socket;

/// Context for WebSocket upgrade operations
pub const SocketUpgradeContext = struct {
    req: *httpz.Request,
    res: *httpz.Response,
    allocator: std.mem.Allocator,
    upgraded: bool = false,
    upgrade_data: ?[]const u8 = null,
};

/// Creates a Socket with upgrade capability (pre-upgrade, for RouteContext)
pub fn createUpgradeSocket(upgrade_ctx: *SocketUpgradeContext) Socket {
    return Socket{
        .backend_ctx = @ptrCast(upgrade_ctx),
        .vtable = &socket_upgrade_vtable,
    };
}

const socket_upgrade_vtable = Socket.VTable{
    .upgrade = &socketUpgrade,
    .upgradeWithData = &socketUpgradeWithData,
    .write = &socketUpgradeWrite,
    .read = &socketUpgradeRead,
    .close = &socketUpgradeClose,
    // Pub/Sub no-ops for pre-upgrade socket (not yet a WebSocket)
    .subscribe = &socketUpgradeSubscribe,
    .unsubscribe = &socketUpgradeUnsubscribe,
    .publish = &socketUpgradePublish,
    .isSubscribed = &socketUpgradeIsSubscribed,
    .setPublishToSelf = &socketUpgradeSetPublishToSelf,
};

fn socketUpgradeSubscribe(_: *anyopaque, _: []const u8) void {
    // No-op: socket not yet upgraded to WebSocket
}

fn socketUpgradeUnsubscribe(_: *anyopaque, _: []const u8) void {
    // No-op: socket not yet upgraded to WebSocket
}

fn socketUpgradePublish(_: *anyopaque, _: []const u8, _: []const u8) usize {
    // No-op: socket not yet upgraded to WebSocket
    return 0;
}

fn socketUpgradeIsSubscribed(_: *anyopaque, _: []const u8) bool {
    // No-op: socket not yet upgraded to WebSocket
    return false;
}

fn socketUpgradeSetPublishToSelf(_: *anyopaque, _: bool) void {
    // No-op: socket not yet upgraded to WebSocket
}

fn socketUpgrade(ctx: *anyopaque) anyerror!void {
    const upgrade_ctx: *SocketUpgradeContext = @ptrCast(@alignCast(ctx));
    // Mark as upgraded - the actual httpz.upgradeWebsocket call happens in the handler
    upgrade_ctx.upgraded = true;
}

fn socketUpgradeWithData(ctx: *anyopaque, data_bytes: []const u8) anyerror!void {
    const upgrade_ctx: *SocketUpgradeContext = @ptrCast(@alignCast(ctx));
    // TODO: Use parent allocator which is persistent
    // the HTTP request, but upgrade_data needs to persist for the WebSocket lifetime
    upgrade_ctx.upgraded = true;
    const copied_data = std.heap.page_allocator.alloc(u8, data_bytes.len) catch return error.OutOfMemory;
    @memcpy(copied_data, data_bytes);
    upgrade_ctx.upgrade_data = copied_data;
}

fn socketUpgradeWrite(_: *anyopaque, _: []const u8) anyerror!void {
    // Cannot write before upgrade is complete
    return error.WebSocketNotConnected;
}

fn socketUpgradeRead(_: *anyopaque) ?[]const u8 {
    // Cannot read before upgrade is complete
    return null;
}

fn socketUpgradeClose(_: *anyopaque) void {
    // No-op before upgrade
}

/// Context for active WebSocket connections
pub const SocketConnectionContext = struct {
    conn: *httpz.websocket.Conn,
};

/// Creates a Socket for an active WebSocket connection (post-upgrade, for SocketContext)
pub fn createConnectionSocket(conn_ctx: *SocketConnectionContext) Socket {
    return Socket{
        .backend_ctx = @ptrCast(conn_ctx),
        .vtable = &socket_connection_vtable,
    };
}

const socket_connection_vtable = Socket.VTable{
    .upgrade = &socketConnectionUpgrade,
    .upgradeWithData = &socketConnectionUpgradeWithData,
    .write = &socketConnectionWrite,
    .read = &socketConnectionRead,
    .close = &socketConnectionClose,
};

fn socketConnectionUpgrade(_: *anyopaque) anyerror!void {
    // Already upgraded
    return error.WebSocketAlreadyConnected;
}

fn socketConnectionUpgradeWithData(_: *anyopaque, _: []const u8) anyerror!void {
    // Already upgraded
    return error.WebSocketAlreadyConnected;
}

fn socketConnectionWrite(ctx: *anyopaque, data: []const u8) anyerror!void {
    const conn_ctx: *SocketConnectionContext = @ptrCast(@alignCast(ctx));
    try conn_ctx.conn.write(data);
}

fn socketConnectionRead(_: *anyopaque) ?[]const u8 {
    // Read is handled via clientMessage callback in httpz
    return null;
}

fn socketConnectionClose(ctx: *anyopaque) void {
    const conn_ctx: *SocketConnectionContext = @ptrCast(@alignCast(ctx));
    conn_ctx.conn.close() catch {};
}
