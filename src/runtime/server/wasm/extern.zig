/// ns selects the binding; writes value to buf.
/// Returns byte length, -1 if not found, -2 if buf too small.
pub extern "__zx_kv" fn kv_get(
    ns_ptr: [*]const u8,
    ns_len: usize,
    key_ptr: [*]const u8,
    key_len: usize,
    buf_ptr: [*]u8,
    buf_max: usize,
) i32;

/// Returns 0 on success, negative on error.
pub extern "__zx_kv" fn kv_put(
    ns_ptr: [*]const u8,
    ns_len: usize,
    key_ptr: [*]const u8,
    key_len: usize,
    val_ptr: [*]const u8,
    val_len: usize,
) i32;

/// Returns 0 on success, negative on error.
pub extern "__zx_kv" fn kv_delete(
    ns_ptr: [*]const u8,
    ns_len: usize,
    key_ptr: [*]const u8,
    key_len: usize,
) i32;

/// Writes a JSON array of key names into buf. Returns byte length, -2 if too small.
pub extern "__zx_kv" fn kv_list(
    ns_ptr: [*]const u8,
    ns_len: usize,
    prefix_ptr: [*]const u8,
    prefix_len: usize,
    buf_ptr: [*]u8,
    buf_max: usize,
) i32;

pub extern "__zx_db" fn db_open(
    ns_ptr: [*]const u8,
    ns_len: usize,
) i32;

pub extern "__zx_db" fn db_run(
    ns_ptr: [*]const u8,
    ns_len: usize,
    sql_ptr: [*]const u8,
    sql_len: usize,
    bindings_ptr: [*]const u8,
    bindings_len: usize,
    buf_ptr: [*]u8,
    buf_max: usize,
) i32;

pub extern "__zx_db" fn db_get(
    ns_ptr: [*]const u8,
    ns_len: usize,
    sql_ptr: [*]const u8,
    sql_len: usize,
    bindings_ptr: [*]const u8,
    bindings_len: usize,
    buf_ptr: [*]u8,
    buf_max: usize,
) i32;

pub extern "__zx_db" fn db_all(
    ns_ptr: [*]const u8,
    ns_len: usize,
    sql_ptr: [*]const u8,
    sql_len: usize,
    bindings_ptr: [*]const u8,
    bindings_len: usize,
    buf_ptr: [*]u8,
    buf_max: usize,
) i32;

pub extern "__zx_db" fn db_values(
    ns_ptr: [*]const u8,
    ns_len: usize,
    sql_ptr: [*]const u8,
    sql_len: usize,
    bindings_ptr: [*]const u8,
    bindings_len: usize,
    buf_ptr: [*]u8,
    buf_max: usize,
) i32;

// ---------------------------------------------------------------------------
// WebSocket WASI bridge — Cloudflare Worker binding
// ---------------------------------------------------------------------------

/// Extern imports provided by worker.ts via the __zx_ws import namespace.
/// ws_recv is wrapped with WebAssembly.Suspending on the JS side so that
/// WASM suspends until a message arrives (JSPI).
pub extern "__zx_ws" fn ws_upgrade() void;
pub extern "__zx_ws" fn ws_write(ptr: [*]const u8, len: usize) void;
pub extern "__zx_ws" fn ws_close(code: u16, reason_ptr: [*]const u8, reason_len: usize) void;
/// Returns number of bytes written to buf_ptr, or -1 when the connection closes.
pub extern "__zx_ws" fn ws_recv(buf_ptr: [*]u8, buf_max: usize) i32;
pub extern "__zx_ws" fn ws_subscribe(topic_ptr: [*]const u8, topic_len: usize) void;
pub extern "__zx_ws" fn ws_unsubscribe(topic_ptr: [*]const u8, topic_len: usize) void;
/// Returns number of recipients the message was sent to.
pub extern "__zx_ws" fn ws_publish(topic_ptr: [*]const u8, topic_len: usize, data_ptr: [*]const u8, data_len: usize) usize;
/// Returns 1 if subscribed, 0 otherwise.
pub extern "__zx_ws" fn ws_is_subscribed(topic_ptr: [*]const u8, topic_len: usize) i32;

// ---------------------------------------------------------------------------
// Logging bridge — forwards std.log calls to the JS console with level info
// ---------------------------------------------------------------------------

/// Provided by the JS runtime via the __zx namespace (ZxBridge).
/// level: 0=error, 1=warn, 2=info, 3=debug
pub extern "__zx" fn _log(level: u8, ptr: [*]const u8, len: usize) void;
