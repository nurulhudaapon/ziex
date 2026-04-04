const std = @import("std");
const builtin = @import("builtin");
const zx = @import("../../root.zig");

const Router = zx.Router;
const Component = zx.Component;
const Allocator = std.mem.Allocator;
const Request = @import("Request.zig");
const Response = @import("Response.zig");
const server_dispatch = @import("../server/dispatch.zig");
const render = @import("../server/render.zig");
const zx_injections = @import("zx_injections");
const tree = @import("tree.zig");

pub const ServerMeta = zx.server.ServerMeta;
pub const Route = ServerMeta.Route;
pub const ProxyResult = Router.ProxyResult;

/// Result of page handling.
pub const PageResult = union(enum) {
    /// Successfully rendered page component (with layouts + injections applied).
    component: Component,
    /// Request was handled by JS action dispatch. Response body is set.
    action_handled: struct { body: ?[]u8 = null },
    /// Action was invoked natively (form POST). Continue rendering the page.
    action_native: void,
    /// Request was handled by server event dispatch.
    event_handled: struct { body: ?[]u8 = null },
    /// No page handler for this route.
    not_found: void,
    /// Error during page rendering.
    page_error: anyerror,
    /// Action handler not found.
    action_not_found: void,
    /// Event handler not found.
    event_not_found: void,
};

/// Result of API handling.
pub const ApiResult = union(enum) {
    /// Request handled successfully.
    handled: void,
    /// No route handlers defined.
    not_found: void,
    /// Error during handler execution.
    handler_error: anyerror,
};

/// Execute cascading + page-local proxy chain for a page route.
pub fn executePageProxy(route: *const Route, request: Request, response: Response, arena: Allocator) ProxyResult {
    return Router.executeProxyChain(route.path, route.page_proxy, request, response, arena);
}

/// Execute cascading + route-local proxy chain for an API route.
pub fn executeRouteProxy(route: *const Route, request: Request, response: Response, arena: Allocator) ProxyResult {
    return Router.executeProxyChain(route.path, route.route_proxy, request, response, arena);
}

/// Execute cascading proxy chain for not-found handling (no local proxy).
pub fn executeNotFoundProxy(pathname: []const u8, request: Request, response: Response, arena: Allocator) ProxyResult {
    return Router.executeProxyChain(pathname, null, request, response, arena);
}

/// Handle a page request.
///
/// Performs action/event dispatch, renders the page component, applies
/// layout hierarchy, and injects build-time HTML. Returns the final
/// component ready to be serialized by the backend.
///
/// The caller is responsible for:
/// - Proxy execution (call `executePageProxy` before this)
/// - Writing the component to the response (streaming or buffered)
/// - Dev-mode features (dev script injection, logging)
/// - Caching
pub fn handlePage(
    route: *const Route,
    request: Request,
    response: Response,
    allocator: Allocator,
    arena: Allocator,
    app_ctx: ?*anyopaque,
    proxy_state_ptr: ?*const anyopaque,
) !PageResult {
    var pagectx = zx.PageContext.initWithAppPtr(app_ctx, request, response, allocator);
    pagectx._state_ptr = proxy_state_ptr;

    const page_fn = route.page orelse return .not_found;

    // -- Server action dispatch --
    switch (try server_dispatch.dispatchAction(request, response, allocator, arena, route.path, pagectx, page_fn)) {
        .not_triggered => {},
        .ok => |r| return .{ .action_handled = .{ .body = r.body } },
        .ok_native => {},
        .not_found => return .action_not_found,
        .page_error => |err| return .{ .page_error = err },
    }

    // -- Server event dispatch --
    switch (try server_dispatch.dispatchServerEvent(request, allocator, arena, route.path, pagectx, page_fn)) {
        .not_triggered => {},
        .ok => |r| return .{ .event_handled = .{ .body = r.body } },
        .ok_native => {},
        .not_found => return .event_not_found,
        .page_error => |err| return .{ .page_error = err },
    }

    // -- Render page --
    render.current_route_path = route.path;

    var page_component = page_fn(pagectx) catch |err| {
        render.current_route_path = null;
        return .{ .page_error = err };
    };

    // -- Apply layout hierarchy --
    var layoutctx = zx.LayoutContext.initWithAppPtr(app_ctx, request, response, allocator);
    layoutctx._state_ptr = proxy_state_ptr;
    page_component = Router.applyLayouts(route, request.pathname, layoutctx, page_component);

    // -- Inject build-time HTML (scripts, styles, etc.) --
    injectZxInjections(arena, &page_component);

    return .{ .component = page_component };
}

/// Handle an API request.
///
/// Resolves the handler based on HTTP method and calls it.
/// For WebSocket routes, the caller should pass a backend-specific Socket
/// and check for upgrades after this returns.
///
/// The caller is responsible for:
/// - Proxy execution (call `executeRouteProxy` before this)
/// - WebSocket upgrade detection and completion
/// - Error rendering on handler_error
pub fn handleApi(
    route: *const Route,
    request: Request,
    response: Response,
    allocator: Allocator,
    app_ctx: ?*anyopaque,
    proxy_state_ptr: ?*const anyopaque,
    socket: zx.Socket,
) ApiResult {
    const handlers = route.route orelse return .not_found;

    // Resolve handler for HTTP method
    const route_fn = Router.resolveCustomHandler(handlers, request.method, request.method_str) orelse return .not_found;

    if (handlers.socket != null) {
        var routectx = zx.RouteContext.initWithAppPtrAndSocket(app_ctx, request, response, socket, allocator);
        routectx._state_ptr = proxy_state_ptr;
        route_fn(routectx) catch |err| return .{ .handler_error = err };
    } else {
        var routectx = zx.RouteContext.initWithAppPtr(app_ctx, request, response, allocator);
        routectx._state_ptr = proxy_state_ptr;
        route_fn(routectx) catch |err| return .{ .handler_error = err };
    }

    return .handled;
}

/// Render a not-found page with layout hierarchy.
/// Returns the rendered component, or null if no notfound handler found.
pub fn renderNotFound(
    pathname: []const u8,
    request: Request,
    response: Response,
    allocator: Allocator,
    matched_route: ?*const Route,
) ?Component {
    return Router.renderNotFoundComponent(allocator, request, response, pathname, matched_route);
}

/// Render an error page with layout hierarchy.
/// Returns the rendered component, or null if no error handler found.
pub fn renderError(
    pathname: []const u8,
    request: Request,
    response: Response,
    allocator: Allocator,
    err: anyerror,
) ?Component {
    return Router.renderErrorComponent(allocator, request, response, pathname, err);
}

// TODO: move to injecting structured elmeents from build system and render in here
/// Inject build-time HTML (scripts, styles, etc.) into head/body elements.
/// This handles zx_injections (head_starting, head_ending, body_starting, body_ending).
pub fn injectZxInjections(allocator: Allocator, page: *Component) void {
    if (zx_injections.head_starting.len > 0) {
        if (tree.getElementByName(page, allocator, .head)) |el|
            tree.prependChild(el, allocator, .{ .text = zx_injections.head_starting }) catch {};
    }
    if (zx_injections.head_ending.len > 0) {
        if (tree.getElementByName(page, allocator, .head)) |el|
            tree.appendChild(el, allocator, .{ .text = zx_injections.head_ending }) catch {};
    }
    if (zx_injections.body_starting.len > 0) {
        if (tree.getElementByName(page, allocator, .body)) |el|
            tree.prependChild(el, allocator, .{ .text = zx_injections.body_starting }) catch {};
    }
    if (zx_injections.body_ending.len > 0) {
        if (tree.getElementByName(page, allocator, .body)) |el|
            tree.appendChild(el, allocator, .{ .text = zx_injections.body_ending }) catch {};
    }
}

/// Check if streaming is enabled for a route.
pub fn isStreamingEnabled(route: *const Route) bool {
    if (route.page_opts) |opts| return opts.streaming;
    return false;
}
