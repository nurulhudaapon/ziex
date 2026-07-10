const std = @import("std");
const Fetch = @import("../Fetch.zig");

const Response = Fetch.Response;
const Headers = Fetch.Headers;
const RequestInit = Fetch.RequestInit;
const FetchError = Fetch.FetchError;

const max_response_bytes = 16 * 1024 * 1024;

/// Perform a blocking HTTP fetch via the JS `fetch` import (JSPI).
pub fn fetch(allocator: std.mem.Allocator, url: []const u8, init: RequestInit) FetchError!Response {
    const method_str = @tagName(init.method);
    var headers_buf: [8192]u8 = undefined;
    const headers_json = serializeHeadersJson(init.headers, &headers_buf);
    const body = init.body orelse "";

    var status: u16 = 0;
    var capacity: usize = 65536;
    var buf = try allocator.alloc(u8, capacity);
    defer allocator.free(buf);

    while (true) {
        const n = ext.fetch(
            url.ptr,
            url.len,
            method_str.ptr,
            method_str.len,
            headers_json.ptr,
            headers_json.len,
            body.ptr,
            body.len,
            init.timeout_ms,
            &status,
            buf.ptr,
            capacity,
        );

        if (n == -2) {
            capacity *= 2;
            if (capacity > max_response_bytes) return error.InvalidResponse;
            buf = try allocator.realloc(buf, capacity);
            continue;
        }

        if (n < 0) return error.NetworkError;

        const body_data = try allocator.dupe(u8, buf[0..@intCast(n)]);

        return Response{
            .status = status,
            .status_text = statusText(status),
            .headers = Headers.init(allocator),
            ._body = body_data,
            ._body_used = false,
            ._allocator = allocator,
            ._owns_memory = true,
        };
    }
}

const ext = struct {
    pub extern "__zx_net" fn fetch(
        url_ptr: [*]const u8,
        url_len: usize,
        method_ptr: [*]const u8,
        method_len: usize,
        headers_ptr: [*]const u8,
        headers_len: usize,
        body_ptr: [*]const u8,
        body_len: usize,
        timeout_ms: u32,
        status_out: *u16,
        buf_ptr: [*]u8,
        buf_max: usize,
    ) i32;
};

fn serializeHeadersJson(headers: ?[]const RequestInit.Header, buf: []u8) []const u8 {
    var len: usize = 0;
    buf[len] = '{';
    len += 1;

    if (headers) |hdrs| {
        for (hdrs, 0..) |h, i| {
            if (i > 0) {
                buf[len] = ',';
                len += 1;
            }
            buf[len] = '"';
            len += 1;
            const name_end = @min(len + h.name.len, buf.len - 10);
            @memcpy(buf[len..name_end], h.name[0..@min(h.name.len, name_end - len)]);
            len = name_end;
            buf[len] = '"';
            len += 1;
            buf[len] = ':';
            len += 1;
            buf[len] = '"';
            len += 1;
            const val_end = @min(len + h.value.len, buf.len - 2);
            @memcpy(buf[len..val_end], h.value[0..@min(h.value.len, val_end - len)]);
            len = val_end;
            buf[len] = '"';
            len += 1;
        }
    }

    buf[len] = '}';
    len += 1;
    return buf[0..len];
}

fn statusText(code: u16) []const u8 {
    return switch (code) {
        200 => "OK",
        201 => "Created",
        204 => "No Content",
        301 => "Moved Permanently",
        302 => "Found",
        304 => "Not Modified",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        500 => "Internal Server Error",
        else => "Unknown",
    };
}
