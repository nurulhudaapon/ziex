const std = @import("std");
const httpz = @import("httpz");
const Http = @import("../Http.zig");
const Request = @import("Request.zig");
const Response = @import("Response.zig");
const common = @import("common.zig");
const MultiFormData = @import("MultiFormData.zig");

// --- Method / protocol conversion --- //
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
        .OTHER => .CONNECT,
    };
}

fn convertProtocol(protocol: httpz.Protocol) std.http.Version {
    return switch (protocol) {
        .HTTP10 => .@"HTTP/1.0",
        .HTTP11 => .@"HTTP/1.1",
    };
}

// --- Backend context --- //
pub const HttpzCtx = struct {
    req: *httpz.Request,
    res: *httpz.Response,

    pub fn http(self: *HttpzCtx) Http {
        return .{ .userdata = @ptrCast(self), .vtable = &vtable };
    }

    const vtable = Http.VTable{
        .reqText = &reqText,
        .reqHeaderGet = &reqHeaderGet,
        .reqHeaderHas = &reqHeaderHas,
        .reqParam = &reqParam,
        .reqQueryGet = &reqQueryGet,
        .reqQueryHas = &reqQueryHas,
        .reqFormGet = &reqFormGet,
        .reqFormHas = &reqFormHas,
        .reqMultiGet = &reqMultiGet,
        .reqMultiHas = &reqMultiHas,
        .reqMultiGetAll = &reqMultiGetAll,
        .resSetStatus = &resSetStatus,
        .resSetBody = &resSetBody,
        .resHeaderGet = &resHeaderGet,
        .resHeaderSet = &resHeaderSet,
        .resHeaderAdd = &resHeaderAdd,
        .resWriter = &resWriter,
        .resWriteChunk = &resWriteChunk,
        .resClearWriter = &resClearWriter,
        .resSetCookie = &resSetCookie,
        // WebSocket ops are not available on the plain request/response backend.
        .wsUpgrade = Http.failing_vtable.wsUpgrade,
        .wsWrite = Http.failing_vtable.wsWrite,
        .wsRead = Http.failing_vtable.wsRead,
        .wsClose = Http.failing_vtable.wsClose,
        .wsSubscribe = Http.failing_vtable.wsSubscribe,
        .wsUnsubscribe = Http.failing_vtable.wsUnsubscribe,
        .wsPublish = Http.failing_vtable.wsPublish,
        .wsIsSubscribed = Http.failing_vtable.wsIsSubscribed,
        .wsSetPublishToSelf = Http.failing_vtable.wsSetPublishToSelf,
    };

    fn ctx(userdata: ?*anyopaque) *HttpzCtx {
        return @ptrCast(@alignCast(userdata.?));
    }

    // --- request --- //

    fn reqText(userdata: ?*anyopaque) ?[]const u8 {
        return ctx(userdata).req.body();
    }

    fn reqHeaderGet(userdata: ?*anyopaque, name: []const u8) ?[]const u8 {
        return ctx(userdata).req.headers.get(name);
    }

    fn reqHeaderHas(userdata: ?*anyopaque, name: []const u8) bool {
        return ctx(userdata).req.headers.has(name);
    }

    fn reqParam(userdata: ?*anyopaque, name: []const u8) ?[]const u8 {
        return ctx(userdata).req.param(name);
    }

    fn reqQueryGet(userdata: ?*anyopaque, name: []const u8) ?[]const u8 {
        const query = ctx(userdata).req.query() catch return null;
        return query.get(name);
    }

    fn reqQueryHas(userdata: ?*anyopaque, name: []const u8) bool {
        const query = ctx(userdata).req.query() catch return false;
        return query.has(name);
    }

    fn reqFormGet(userdata: ?*anyopaque, name: []const u8) ?[]const u8 {
        if (ctx(userdata).req.formData()) |fd| {
            return fd.get(name);
        } else |_| {}
        return null;
    }

    fn reqFormHas(userdata: ?*anyopaque, name: []const u8) bool {
        if (ctx(userdata).req.formData()) |fd| {
            return fd.has(name);
        } else |_| {}
        return false;
    }

    fn reqMultiGet(userdata: ?*anyopaque, name: []const u8) ?MultiFormData.Value {
        if (ctx(userdata).req.multiFormData()) |mfd| {
            if (mfd.get(name)) |entry| {
                return .{ .data = entry.value, .filename = entry.filename };
            }
        } else |_| {}
        return null;
    }

    fn reqMultiHas(userdata: ?*anyopaque, name: []const u8) bool {
        if (ctx(userdata).req.multiFormData()) |mfd| {
            return mfd.has(name);
        } else |_| {}
        return false;
    }

    fn reqMultiGetAll(userdata: ?*anyopaque, name: []const u8, allocator: std.mem.Allocator) ?[]const MultiFormData.Value {
        const mfd = ctx(userdata).req.multiFormData() catch return null;
        if (mfd.get(name)) |entry| {
            const result = allocator.alloc(MultiFormData.Value, 1) catch return null;
            result[0] = .{ .data = entry.value, .filename = entry.filename };
            return result;
        }
        return null;
    }

    // --- response --- //

    fn resSetStatus(userdata: ?*anyopaque, code: u16) void {
        ctx(userdata).res.status = code;
    }

    fn resSetBody(userdata: ?*anyopaque, content: []const u8) void {
        ctx(userdata).res.body = content;
    }

    fn resHeaderGet(userdata: ?*anyopaque, name: []const u8) ?[]const u8 {
        return ctx(userdata).res.headers.get(name);
    }

    fn resHeaderSet(userdata: ?*anyopaque, name: []const u8, value: []const u8) void {
        ctx(userdata).res.header(name, value);
    }

    fn resHeaderAdd(userdata: ?*anyopaque, name: []const u8, value: []const u8) void {
        ctx(userdata).res.headers.add(name, value);
    }

    fn resWriter(userdata: ?*anyopaque) ?*std.Io.Writer {
        return ctx(userdata).res.writer();
    }

    fn resWriteChunk(userdata: ?*anyopaque, data: []const u8) anyerror!void {
        try ctx(userdata).res.chunk(data);
    }

    fn resClearWriter(userdata: ?*anyopaque) void {
        ctx(userdata).res.clearWriter();
    }

    fn resSetCookie(userdata: ?*anyopaque, name: []const u8, value: []const u8, opts: common.CookieOptions) anyerror!void {
        const res = ctx(userdata).res;
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
};

// --- Facade construction --- //

/// Build an abstract `Request` backed by the given httpz request/response pair.
pub fn createRequest(ctx: *HttpzCtx) Request {
    const inner = ctx.req;
    return (Request.Builder{
        .url = inner.url.raw,
        .method = convertMethod(inner.method),
        .method_str = inner.method_string,
        .pathname = inner.url.path,
        .referrer = inner.headers.get("referer") orelse "",
        .search = inner.url.query,
        .protocol = convertProtocol(inner.protocol),
        .arena = inner.arena,
        .cookie_header = inner.headers.get("cookie") orelse "",
        .http = ctx.http(),
    }).build();
}

/// Build an abstract `Response` backed by the given httpz request/response pair.
pub fn createResponse(ctx: *HttpzCtx, arena: std.mem.Allocator) Response {
    return (Response.Builder{
        .status = ctx.res.status,
        .arena = arena,
        .http = ctx.http(),
    }).build();
}

// --- WebSocket: pre-upgrade --- //

const routing = @import("../Router/routing.zig");
const Socket = routing.Socket;

pub const UpgradeBackend = struct {
    req: *httpz.Request,
    res: *httpz.Response,
    allocator: std.mem.Allocator,
    upgraded: bool = false,
    upgrade_data: ?[]const u8 = null,

    pub fn socket(self: *UpgradeBackend) Socket {
        return .{ ._internal = .{ .http = .{ .userdata = @ptrCast(self), .vtable = &vtable }, .attached = true } };
    }

    const vtable = blk: {
        var vt = Http.failing_vtable;
        vt.wsUpgrade = &wsUpgrade;
        break :blk vt;
    };

    fn ctx(userdata: ?*anyopaque) *UpgradeBackend {
        return @ptrCast(@alignCast(userdata.?));
    }

    fn wsUpgrade(userdata: ?*anyopaque, data: ?[]const u8) anyerror!void {
        const self = ctx(userdata);
        self.upgraded = true;
        if (data) |bytes| {
            // The HTTP request arena is freed after the handler returns, but
            // upgrade_data must persist for the WebSocket lifetime.
            const copied = std.heap.page_allocator.alloc(u8, bytes.len) catch return error.OutOfMemory;
            @memcpy(copied, bytes);
            self.upgrade_data = copied;
        }
    }
};
