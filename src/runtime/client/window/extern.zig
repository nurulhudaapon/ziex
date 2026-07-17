// DOM
/// Create element
pub extern "__zx" fn _ce(id: usize, vnode_id: u64) u64;

/// Create text
pub extern "__zx" fn _ct(ptr: [*]const u8, len: usize, vnode_id: u64) u64;

/// setAttribute on the element identified by vnode_id.
pub extern "__zx" fn _sa(vnode_id: u64, name_ptr: [*]const u8, name_len: usize, val_ptr: [*]const u8, val_len: usize) void;

/// Set property
pub extern "__zx" fn _sp(vnode_id: u64, name_ptr: [*]const u8, name_len: usize, val_ptr: [*]const u8, val_len: usize) void;

/// removeAttribute on the element identified by vnode_id.
pub extern "__zx" fn _ra(vnode_id: u64, name_ptr: [*]const u8, name_len: usize) void;

/// Set nodeValue on the text node identified by vnode_id.
pub extern "__zx" fn _snv(vnode_id: u64, ptr: [*]const u8, len: usize) void;

/// Set innerHTML
pub extern "__zx" fn _srh(vnode_id: u64, ptr: [*]const u8, len: usize) void;

/// parent.appendChild(child)
pub extern "__zx" fn _ac(parent_id: u64, child_id: u64) void;

/// parent.insertBefore(child, ref)
pub extern "__zx" fn _ib(parent_id: u64, child_id: u64, ref_id: u64) void;

/// parent.removeChild(child)
pub extern "__zx" fn _rc(parent_id: u64, child_id: u64) void;

/// parent.replaceChild(new_child, old_child)
pub extern "__zx" fn _rpc(parent_id: u64, new_id: u64, old_id: u64) void;

// Async / timer
pub extern "__zx" fn _setTimeout(callback_id: u64, delay_ms: u32) void;
pub extern "__zx" fn _setInterval(callback_id: u64, interval_ms: u32) void;
pub extern "__zx" fn _clearInterval(callback_id: u64) void;

// WebSocket
pub extern "__zx" fn _wsConnect(ws_id: u64, url_ptr: [*]const u8, url_len: usize, protocols_ptr: [*]const u8, protocols_len: usize) void;
pub extern "__zx" fn _wsSend(ws_id: u64, data_ptr: [*]const u8, data_len: usize, is_binary: u8) void;
pub extern "__zx" fn _wsClose(ws_id: u64, code: u16, reason_ptr: [*]const u8, reason_len: usize) void;

// Location
/// Write window.location.href into buf. Returns the number of bytes written.
pub extern "__zx" fn _getLocationHref(buf: [*]u8, buf_len: usize) usize;

/// Gets form entries `[k1,v1,...]` from JS and writes the pointer to `out_ptr`.
pub extern "__zx" fn _getFormData(event_ref: u64, out_ptr: *[*]u8) usize;

/// Submits a form with action identity
pub extern "__zx" fn _submitFormAction(vnode_id: u64, action_id: u32) void;

/// Submits a form with component states in __$states field
pub extern "__zx" fn _submitFormActionAsync(
    vnode_id: u64,
    action_id: u32,
    states_ptr: [*]const u8,
    states_len: usize,
    fetch_id: u64,
) void;

// Logging
/// Forward a log message to the JS console. level: 0=error, 1=warn, 2=info, 3=debug
pub extern "__zx" fn _log(level: u8, ptr: [*]const u8, len: usize) void;

// Event handler metadata
/// Register whether a delegated event handler for a vnode may suspend.
pub extern "__zx" fn _setEventHandlerMode(vnode_id: u64, event_type_id: u8, may_suspend: u8) void;

/// Clear all delegated event handler metadata for a vnode.
pub extern "__zx" fn _clearEventHandlerModes(vnode_id: u64) void;

// Fetch
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
