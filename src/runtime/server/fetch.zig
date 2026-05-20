//! Server-side Fetch implementation using std.http.Client.
//!
//! This module provides the native Zig HTTP client implementation for server-side
//! fetch operations. It wraps std.http.Client with the Fetch API interface.

const std = @import("std");
const Fetch = @import("../core/Fetch.zig");

const Response = Fetch.Response;
const Headers = Fetch.Headers;
const RequestInit = Fetch.RequestInit;
const FetchError = Fetch.FetchError;

/// Perform an HTTP fetch request using std.http.Client.
pub fn fetch(allocator: std.mem.Allocator, url: []const u8, init: RequestInit) FetchError!Response {
    // Create HTTP client
    var client: std.http.Client = .{ .allocator = allocator, .io = std.Options.debug_io };
    defer client.deinit();

    // Build extra headers as a slice
    var extra_headers_buf: [64]std.http.Header = undefined;
    var extra_headers_len: usize = 0;

    if (init.headers) |headers| {
        for (headers) |h| {
            if (extra_headers_len >= extra_headers_buf.len) break;
            extra_headers_buf[extra_headers_len] = .{ .name = h.name, .value = h.value };
            extra_headers_len += 1;
        }
    }

    const extra_headers = extra_headers_buf[0..extra_headers_len];

    // Create a buffer to collect the response body
    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();

    // Perform the fetch
    const result = client.fetch(.{
        .location = .{ .url = url },
        .method = init.method,
        .payload = init.body,
        .extra_headers = extra_headers,
        .redirect_behavior = if (init.follow_redirects) @enumFromInt(3) else .unhandled,
        .response_writer = &aw.writer,
    }) catch return error.NetworkError;

    // Get status
    const status: u16 = @intFromEnum(result.status);
    const status_text = result.status.phrase() orelse "Unknown";

    // Get the body - duplicate it since aw will be deferred
    const body = allocator.dupe(u8, aw.written()) catch return error.OutOfMemory;

    return Response{
        .status = status,
        .status_text = status_text,
        .headers = Headers.init(allocator),
        ._body = body,
        ._body_used = false,
        ._allocator = allocator,
        ._owns_memory = true,
    };
}
