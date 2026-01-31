pub extern "__zx" fn _ce(id: usize) u64;
pub extern "__zx" fn _setTimeout(callback_id: u64, delay_ms: u32) void;
pub extern "__zx" fn _setInterval(callback_id: u64, interval_ms: u32) void;
pub extern "__zx" fn _clearInterval(callback_id: u64) void;
pub extern "__zx" fn _wsConnect(ws_id: u64, url_ptr: [*]const u8, url_len: usize, protocols_ptr: [*]const u8, protocols_len: usize) void;
pub extern "__zx" fn _wsSend(ws_id: u64, data_ptr: [*]const u8, data_len: usize, is_binary: u8) void;
pub extern "__zx" fn _wsClose(ws_id: u64, code: u16, reason_ptr: [*]const u8, reason_len: usize) void;
pub extern "__zx" fn _fetchAsync(
    url_ptr: [*]const u8,
    url_len: usize,
    method_ptr: [*]const u8,
    method_len: usize,
    headers_ptr: [*]const u8,
    headers_len: usize,
    body_ptr: [*]const u8,
    body_len: usize,
    timeout_ms: u32,
    callback_id: u64,
) void;
