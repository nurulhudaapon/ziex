const std = @import("std");
const builtin = @import("builtin");
const platform = @import("../../platform.zig");

const is_wasm_arch = builtin.cpu.arch == .wasm32 or builtin.cpu.arch == .wasm64;

/// Must match `pkg/ziex/src/wasm/core.ts` CallbackType_* constants.
pub const HostMsg = enum(u8) {
    event = 0,
    fetch_success = 1,
    fetch_error = 2,
    timeout = 3,
    interval = 4,
    ws_open = 5,
    ws_message = 6,
    ws_error = 7,
    ws_close = 8,
};

/// JS writes empty payloads as `(ptr=0, len=0)`. `@ptrFromInt(0)` panics under
/// safety checks, so map that to a non-null empty slice.
fn hostBytes(addr: u64, len: usize) []const u8 {
    if (len == 0) return &.{};
    const ptr: [*]const u8 = @ptrFromInt(@as(usize, @truncate(addr)));
    return ptr[0..len];
}

fn hostCb(msg_type: u8, id: u64, a: u64, b: u64, c: u64) callconv(.c) void {
    if (comptime !is_wasm_arch) return;

    const alloc = std.heap.wasm_allocator;
    const msg: HostMsg = @enumFromInt(msg_type);

    switch (msg) {
        .timeout, .interval, .event => {
            if (comptime platform.platform.role == .client) {
                const window = @import("../client/window.zig");
                const cb_type: window.CallbackType = @enumFromInt(msg_type);
                _ = window.dispatchCallback(cb_type, id, a, alloc);
            }
        },
        .fetch_success, .fetch_error => {
            const fetch = @import("../client/fetch.zig");
            const body = hostBytes(b, @truncate(c));
            const status: u16 = @truncate(a);
            const is_error: u8 = if (msg == .fetch_error) 1 else 0;
            fetch.onFetchComplete(id, status, body.ptr, body.len, is_error);
        },
        .ws_open => {
            if (comptime platform.platform.role == .client) {
                const ws = @import("../client/websocket.zig");
                const protocol = hostBytes(a, @truncate(b));
                ws.onOpen(id, protocol.ptr, protocol.len);
            }
        },
        .ws_message => {
            if (comptime platform.platform.role == .client) {
                const ws = @import("../client/websocket.zig");
                const data = hostBytes(a, @truncate(b));
                ws.onMessage(id, data.ptr, data.len, @truncate(c));
            }
        },
        .ws_error => {
            if (comptime platform.platform.role == .client) {
                const ws = @import("../client/websocket.zig");
                const message = hostBytes(a, @truncate(b));
                ws.onError(id, message.ptr, message.len);
            }
        },
        .ws_close => {
            if (comptime platform.platform.role == .client) {
                const ws = @import("../client/websocket.zig");
                const reason = hostBytes(b, @truncate(c));
                const was_clean: u8 = @truncate(c >> 32);
                ws.onClose(id, @truncate(a), reason.ptr, reason.len, was_clean);
            }
        },
    }
}

comptime {
    if (is_wasm_arch) {
        @export(&hostCb, .{ .name = "__zx_cb" });
    }
}
