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
            const body_ptr: [*]const u8 = @ptrFromInt(@as(usize, @truncate(b)));
            const body_len: usize = @truncate(c);
            const status: u16 = @truncate(a);
            const is_error: u8 = if (msg == .fetch_error) 1 else 0;
            fetch.onFetchComplete(id, status, body_ptr, body_len, is_error);
        },
        .ws_open => {
            if (comptime platform.platform.role == .client) {
                const ws = @import("../client/websocket.zig");
                const ptr: [*]const u8 = @ptrFromInt(@as(usize, @truncate(a)));
                ws.onOpen(id, ptr, @truncate(b));
            }
        },
        .ws_message => {
            if (comptime platform.platform.role == .client) {
                const ws = @import("../client/websocket.zig");
                const ptr: [*]const u8 = @ptrFromInt(@as(usize, @truncate(a)));
                ws.onMessage(id, ptr, @truncate(b), @truncate(c));
            }
        },
        .ws_error => {
            if (comptime platform.platform.role == .client) {
                const ws = @import("../client/websocket.zig");
                const ptr: [*]const u8 = @ptrFromInt(@as(usize, @truncate(a)));
                ws.onError(id, ptr, @truncate(b));
            }
        },
        .ws_close => {
            if (comptime platform.platform.role == .client) {
                const ws = @import("../client/websocket.zig");
                const ptr: [*]const u8 = @ptrFromInt(@as(usize, @truncate(b)));
                const reason_len: usize = @truncate(c);
                const was_clean: u8 = @truncate(c >> 32);
                ws.onClose(id, @truncate(a), ptr, reason_len, was_clean);
            }
        },
    }
}

comptime {
    if (is_wasm_arch) {
        @export(&hostCb, .{ .name = "__zx_cb" });
    }
}
