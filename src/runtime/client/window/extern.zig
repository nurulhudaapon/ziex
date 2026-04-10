/// Create an HTML/SVG element by tag enum id, register it in the JS domNodes
/// registry under vnode_id, and set __zx_ref = vnode_id on the element.
/// Returns the jsz ref (needed to construct the root HTMLElement for CommentMarker).
pub extern "__zx" fn _ce(id: usize, vnode_id: u64) u64;

/// Create a text node with the given content, register it in the JS domNodes
/// registry under vnode_id, and set __zx_ref = vnode_id on the node.
pub extern "__zx" fn _ct(ptr: [*]const u8, len: usize, vnode_id: u64) u64;

// Attribute / property mutation

/// setAttribute on the element identified by vnode_id.
pub extern "__zx" fn _sa(vnode_id: u64, name_ptr: [*]const u8, name_len: usize, val_ptr: [*]const u8, val_len: usize) void;

/// Set a DOM property (not attribute) on the element identified by vnode_id.
/// Used for properties like checked, value, selected, muted where
/// setAttribute does not reflect the current state after user interaction.
pub extern "__zx" fn _sp(vnode_id: u64, name_ptr: [*]const u8, name_len: usize, val_ptr: [*]const u8, val_len: usize) void;

/// removeAttribute on the element identified by vnode_id.
pub extern "__zx" fn _ra(vnode_id: u64, name_ptr: [*]const u8, name_len: usize) void;

/// Set nodeValue on the text node identified by vnode_id.
pub extern "__zx" fn _snv(vnode_id: u64, ptr: [*]const u8, len: usize) void;

// DOM tree mutation

/// parent.appendChild(child) — both nodes looked up by vnode_id.
pub extern "__zx" fn _ac(parent_id: u64, child_id: u64) void;

/// parent.insertBefore(child, ref) — all nodes looked up by vnode_id.
pub extern "__zx" fn _ib(parent_id: u64, child_id: u64, ref_id: u64) void;

/// parent.removeChild(child) — looked up by vnode_id.
/// Also recursively removes all descendants from the JS domNodes registry.
pub extern "__zx" fn _rc(parent_id: u64, child_id: u64) void;

/// parent.replaceChild(new_child, old_child) — looked up by vnode_id.
/// Also removes old_child subtree from the JS domNodes registry.
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

/// Serialize the form data of the form DOM element identified by vnode_id as a
/// URL-encoded string (application/x-www-form-urlencoded).  Returns the number
/// of bytes written to buf (0 if the element is not a form or not found).
pub extern "__zx" fn _getFormData(vnode_id: u64, buf_ptr: [*]u8, buf_len: usize) usize;

/// Submit a form action: reads the DOM form identified by vnode_id, builds a
/// multipart/form-data request with the X-ZX-Action header, and fires it via
/// the JS fetch API.  The browser handles multipart serialization (including
/// file inputs) so no WASM-side encoding is required.
pub extern "__zx" fn _submitFormAction(vnode_id: u64) void;

/// Like _submitFormAction but stateful: injects the serialised bound-state JSON
/// as a `__$states` multipart field and calls __zx_fetch_complete(fetch_id,…)
/// when the response arrives so WASM can apply the returned state updates.
pub extern "__zx" fn _submitFormActionAsync(
    vnode_id: u64,
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
