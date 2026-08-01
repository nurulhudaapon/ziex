const builtin = @import("builtin");
const is_wasm = builtin.cpu.arch == .wasm32 or builtin.cpu.arch == .wasm64;

const wasm_import = struct {
    pub extern "__zx_ws" fn ws_upgrade() void;
    pub extern "__zx_ws" fn ws_write(ptr: [*]const u8, len: usize) void;
    pub extern "__zx_ws" fn ws_close(code: u16, reason_ptr: [*]const u8, reason_len: usize) void;
    pub extern "__zx_ws" fn ws_recv(buf_ptr: [*]u8, buf_max: usize) i32;
    pub extern "__zx_ws" fn ws_subscribe(topic_ptr: [*]const u8, topic_len: usize) void;
    pub extern "__zx_ws" fn ws_unsubscribe(topic_ptr: [*]const u8, topic_len: usize) void;
    pub extern "__zx_ws" fn ws_publish(topic_ptr: [*]const u8, topic_len: usize, data_ptr: [*]const u8, data_len: usize) usize;
    pub extern "__zx_ws" fn ws_is_subscribed(topic_ptr: [*]const u8, topic_len: usize) i32;

    /// Commit response status + meta JSON (`{"streaming":bool,"headers":[[name,value],...]}`).
    pub extern "__zx_http" fn commit(status: u16, meta_ptr: [*]const u8, meta_len: usize) void;
    /// Write body bytes into the host response stream.
    pub extern "__zx_http" fn write(ptr: [*]const u8, len: usize) void;
    /// Finish the response body.
    pub extern "__zx_http" fn end() void;

    /// level: 0=error, 1=warn, 2=info, 3=debug
    pub extern "__zx" fn _log(level: u8, ptr: [*]const u8, len: usize) void;
};

pub fn ws_upgrade() void {
    if (is_wasm) wasm_import.ws_upgrade();
}
pub fn ws_write(ptr: [*]const u8, len: usize) void {
    if (is_wasm) wasm_import.ws_write(ptr, len);
}
pub fn ws_close(code: u16, reason_ptr: [*]const u8, reason_len: usize) void {
    if (is_wasm) wasm_import.ws_close(code, reason_ptr, reason_len);
}
pub fn ws_recv(buf_ptr: [*]u8, buf_max: usize) i32 {
    return if (is_wasm) wasm_import.ws_recv(buf_ptr, buf_max) else -1;
}
pub fn ws_subscribe(topic_ptr: [*]const u8, topic_len: usize) void {
    if (is_wasm) wasm_import.ws_subscribe(topic_ptr, topic_len);
}
pub fn ws_unsubscribe(topic_ptr: [*]const u8, topic_len: usize) void {
    if (is_wasm) wasm_import.ws_unsubscribe(topic_ptr, topic_len);
}
pub fn ws_publish(topic_ptr: [*]const u8, topic_len: usize, data_ptr: [*]const u8, data_len: usize) usize {
    return if (is_wasm) wasm_import.ws_publish(topic_ptr, topic_len, data_ptr, data_len) else 0;
}
pub fn ws_is_subscribed(topic_ptr: [*]const u8, topic_len: usize) i32 {
    return if (is_wasm) wasm_import.ws_is_subscribed(topic_ptr, topic_len) else 0;
}

pub fn http_commit(status: u16, meta_ptr: [*]const u8, meta_len: usize) void {
    if (is_wasm) wasm_import.commit(status, meta_ptr, meta_len);
}
pub fn http_write(ptr: [*]const u8, len: usize) void {
    if (is_wasm) wasm_import.write(ptr, len);
}
pub fn http_end() void {
    if (is_wasm) wasm_import.end();
}

/// level: 0=error, 1=warn, 2=info, 3=debug
pub fn _log(level: u8, ptr: [*]const u8, len: usize) void {
    if (is_wasm) wasm_import._log(level, ptr, len);
}
