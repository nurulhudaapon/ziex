//! Shared server action and server event dispatch logic.
//!
//! Used by both handler.zig (full HTTP server) and Edge.zig (WASI edge functions)
//! to avoid duplicating fast/slow-path dispatch logic.

const std = @import("std");
const zx = @import("../../root.zig");
const registry = @import("registry.zig");
const render = @import("render.zig");

pub const PageFn = *const fn (zx.PageContext) anyerror!zx.Component;

pub const DispatchResult = union(enum) {
    /// Request did not match this handler type — continue normal handling.
    not_triggered,
    /// Handler was invoked successfully. `body` is serialized JSON state, or null if no state.
    ok: struct { body: ?[]u8 = null },
    /// Action was invoked natively (form POST). Continue rendering the page.
    ok_native,
    /// Handler was triggered but no registered handler was found after render.
    not_found,
    /// Page function raised an error during slow-path render.
    page_error: anyerror,
};

/// Returns true if the request is a server action request.
/// Checks for the x-zx-action header (JS fetch) or __$action in the form body (no-JS form POST).
pub fn isActionRequest(request: zx.server.Request) bool {
    if (request.headers.has("x-zx-action")) return true;
    const body = request.text() orelse return false;
    const ct = request.headers.get("content-type") orelse "";
    return std.mem.indexOf(u8, body, "__$action=") != null or
        (std.mem.indexOf(u8, ct, "multipart/form-data") != null and
            std.mem.indexOf(u8, body, "name=\"__$action\"") != null);
}

fn parseActionId(request: zx.server.Request) u32 {
    if (request.headers.get("x-zx-action")) |raw| {
        return std.fmt.parseInt(u32, raw, 10) catch 1;
    }

    const content_type = request.headers.get("content-type") orelse "";
    if (std.mem.indexOf(u8, content_type, "multipart/form-data") != null) {
        const raw = request.multiFormData().getValue("__$action") orelse return 1;
        return std.fmt.parseInt(u32, raw, 10) catch 1;
    }

    const raw = request.formData().get("__$action") orelse return 1;
    return std.fmt.parseInt(u32, raw, 10) catch 1;
}

fn serializeStateOutputs(sc: anytype, allocator: std.mem.Allocator) !?[]u8 {
    var aw = std.Io.Writer.Allocating.init(allocator);
    try zx.util.zxon.serialize(sc._outputs, &aw.writer, .{});
    return aw.written();
}

fn slowPathRender(
    page_fn: PageFn,
    pagectx: zx.PageContext,
    route_path: []const u8,
    arena: std.mem.Allocator,
) ?anyerror {
    var page_component = page_fn(pagectx) catch |err| return err;
    var discard = std.Io.Writer.Allocating.init(arena);
    render.current_route_path = route_path;
    page_component.render(&discard.writer) catch {};
    render.current_route_path = null;
    return null;
}

/// Dispatches a server action request. Performs a fast-path registry lookup and falls back
/// to rendering the page to populate the registry before retrying.
/// Returns `not_triggered` if the request is not a server action.
pub fn dispatchAction(
    request: zx.server.Request,
    response: zx.server.Response,
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    route_path: []const u8,
    pagectx: zx.PageContext,
    page_fn: ?PageFn,
) !DispatchResult {
    if (!isActionRequest(request)) return .not_triggered;

    const is_js = request.headers.has("x-zx-action");
    const action_id = parseActionId(request);

    // TODO: cleanup
    // const sr = request.multiFormData().getValue("__$states") orelse "null";

    // std.debug.print("IsJS: {}\nStates: {s}", .{ is_js, sr });

    // Parse state inputs for stateful actions.
    // JS path (X-ZX-Action header): states are the entire JSON body.
    // Form path (_submitFormActionAsync): states are in the __$states multipart field.
    const action_inputs: ?[]const []const u8 = if (false) blk: {
        const body_text = request.text() orelse break :blk null;
        break :blk zx.util.zxon.parse([]const []const u8, arena, body_text, .{}) catch null;
    } else blk: {
        const states_raw = request.multiFormData().getValue("__$states") orelse break :blk null;
        break :blk zx.util.zxon.parse([]const []const u8, arena, states_raw, .{}) catch null;
    };

    if (registry.get(route_path, action_id)) |action_fn| {
        var action_ctx = zx.server.Action{
            .request = request,
            .response = response,
            .allocator = allocator,
            .arena = arena,
            ._inputs = action_inputs,
        };
        action_fn(&action_ctx);
        const body = if (action_ctx._state_ctx) |sc| try serializeStateOutputs(sc, allocator) else null;
        return if (is_js) .{ .ok = .{ .body = body } } else .ok_native;
    }

    // Slow path: render the page to populate the registry, then retry.
    if (page_fn) |pfn| {
        if (slowPathRender(pfn, pagectx, route_path, arena)) |err| {
            return .{ .page_error = err };
        }
    }

    if (registry.get(route_path, action_id)) |action_fn| {
        var action_ctx = zx.server.Action{
            .request = request,
            .response = response,
            .allocator = allocator,
            .arena = arena,
            ._inputs = action_inputs,
        };
        action_fn(&action_ctx);
        const body = if (action_ctx._state_ctx) |sc| try serializeStateOutputs(sc, allocator) else null;
        return if (is_js) .{ .ok = .{ .body = body } } else .ok_native;
    }

    return .not_found;
}

/// Dispatches a server event request. Performs a fast-path registry lookup and falls back
/// to rendering the page to populate the registry before retrying.
/// Returns `not_triggered` if the request is not a server event.
pub fn dispatchServerEvent(
    request: zx.server.Request,
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    route_path: []const u8,
    pagectx: zx.PageContext,
    page_fn: ?PageFn,
) !DispatchResult {
    if (!request.headers.has("x-zx-server-event")) return .not_triggered;

    const payload = zx.util.zxon.parse(zx.EventHandler.Payload, arena, request.text() orelse return .not_found, .{}) catch return .not_found;

    if (registry.getEvent(route_path, payload.handler_id)) |event_fn| {
        var event_ctx = zx.server.Event{
            .allocator = allocator,
            .arena = arena,
            .payload = payload,
        };
        event_fn(&event_ctx);
        const body = if (event_ctx._state_ctx) |sc| try serializeStateOutputs(sc, allocator) else null;
        return .{ .ok = .{ .body = body } };
    }

    // Slow path: render the page to populate the registry, then retry.
    if (page_fn) |pfn| {
        if (slowPathRender(pfn, pagectx, route_path, arena)) |err| {
            return .{ .page_error = err };
        }
    }

    if (registry.getEvent(route_path, payload.handler_id)) |event_fn| {
        var event_ctx = zx.server.Event{
            .allocator = allocator,
            .arena = arena,
            .payload = payload,
        };
        event_fn(&event_ctx);
        const body = if (event_ctx._state_ctx) |sc| try serializeStateOutputs(sc, allocator) else null;
        return .{ .ok = .{ .body = body } };
    }

    return .not_found;
}
