//! Client-side (WASM/Browser) Fetch implementation.
//!
//! Uses JavaScript's native fetch() API via WASM interop.

const std = @import("std");
const builtin = @import("builtin");
const window = @import("window.zig");
const ext = @import("window/extern.zig");
const Fetch = @import("../core/Fetch.zig");

const Response = Fetch.Response;
const Headers = Fetch.Headers;
const RequestInit = Fetch.RequestInit;
const FetchError = Fetch.FetchError;
const ResponseCallback = Fetch.ResponseCallback;

pub const is_wasm = window.is_wasm;
var next_fetch_id: u64 = 1;

// ============================================================================
// Async Fetch
// ============================================================================

/// Perform an async HTTP fetch request with callback.
pub fn fetchAsync(
    allocator: std.mem.Allocator,
    url: []const u8,
    init: RequestInit,
    callback: ResponseCallback,
) void {
    const fetch_id = next_fetch_id;
    next_fetch_id +%= 1;

    // Store callback in registry
    const slot_index = findOrAllocSlot(fetch_id);
    if (slot_index == null) {
        callback(null, error.TooManyPendingRequests);
        return;
    }

    pending_slots[slot_index.?] = PendingFetch{
        .active = true,
        .fetch_id = fetch_id,
        .callback = callback,
        .allocator = allocator,
    };

    // Serialize request
    const method_str = @tagName(init.method);
    var headers_buf: [8192]u8 = undefined;
    const headers_json = serializeHeadersJson(init.headers, &headers_buf);
    const body = init.body orelse "";

    ext._fetchAsync(
        url.ptr,
        url.len,
        method_str.ptr,
        method_str.len,
        headers_json.ptr,
        headers_json.len,
        body.ptr,
        body.len,
        init.timeout_ms,
        fetch_id,
    );
}

// ============================================================================
// Callback Registry
// ============================================================================

const MAX_PENDING = 64;

const PendingFetch = struct {
    active: bool = false,
    fetch_id: u64 = 0,
    callback: ?ResponseCallback = null,
    allocator: std.mem.Allocator = undefined,
};

var pending_slots: [MAX_PENDING]PendingFetch = [_]PendingFetch{.{}} ** MAX_PENDING;

fn findOrAllocSlot(fetch_id: u64) ?usize {
    const preferred: usize = @intCast(fetch_id % MAX_PENDING);
    if (!pending_slots[preferred].active) {
        return preferred;
    }
    for (&pending_slots, 0..) |*slot, i| {
        if (!slot.active) return i;
    }
    return null;
}

fn findSlotByFetchId(fetch_id: u64) ?usize {
    const preferred: usize = @intCast(fetch_id % MAX_PENDING);
    if (pending_slots[preferred].active and pending_slots[preferred].fetch_id == fetch_id) {
        return preferred;
    }
    for (&pending_slots, 0..) |*slot, i| {
        if (slot.active and slot.fetch_id == fetch_id) return i;
    }
    return null;
}

/// Called by JS when async fetch completes
export fn __zx_fetch_complete(
    fetch_id: u64,
    status_code: u16,
    body_ptr: [*]const u8,
    body_len: usize,
    is_error: u8,
) void {
    const slot_idx = findSlotByFetchId(fetch_id) orelse return;
    var slot = &pending_slots[slot_idx];

    const callback = slot.callback orelse return;
    const allocator = slot.allocator;

    slot.active = false;
    slot.callback = null;

    if (is_error != 0) {
        callback(null, error.NetworkError);
        return;
    }

    // Copy body data
    const body_data = if (body_len > 0)
        allocator.dupe(u8, body_ptr[0..body_len]) catch {
            callback(null, error.OutOfMemory);
            return;
        }
    else
        @as([]const u8, "");

    // Allocate Response on heap
    const response = allocator.create(Response) catch {
        if (body_data.len > 0) allocator.free(body_data);
        callback(null, error.OutOfMemory);
        return;
    };

    response.* = Response{
        .status = status_code,
        .status_text = statusText(status_code),
        .headers = Headers.init(allocator),
        ._body = body_data,
        ._body_used = false,
        ._allocator = allocator,
        ._owns_memory = true,
    };

    callback(response, null);
}

// ============================================================================
// Helpers
// ============================================================================

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
