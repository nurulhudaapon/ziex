//! Shared routing logic for edge (WASI) and server runtimes.
//! Provides route matching, proxy cascading, layout hierarchy,
//! error/notfound page rendering, action streaming, and handler registry.

const std = @import("std");
const zx = @import("../../root.zig");

const Component = zx.Component;
const ServerMeta = zx.server.ServerMeta;
const Route = ServerMeta.Route;

pub const FindRouteOptions = struct {
    match: enum { closest, exact } = .exact,
    has_notfound: bool = false,
    has_error: bool = false,
};

pub const Param = struct {
    name: []const u8,
    value: []const u8,
};

/// Holds the result of a pattern-matched route lookup, including any extracted URL params.
pub const RouteMatch = struct {
    route: *const Route,
    params: [8]Param = undefined,
    param_count: usize = 0,

    pub fn getParam(self: *const RouteMatch, name: []const u8) ?[]const u8 {
        for (self.params[0..self.param_count]) |p| {
            if (std.mem.eql(u8, p.name, name)) return p.value;
        }
        return null;
    }
};

pub const ProxyResult = struct {
    aborted: bool = false,
    state_ptr: ?*const anyopaque = null,
};

/// Execute cascading Proxy() handlers from root "/" down to the target path, plus optional local proxy.
pub fn executeProxyChain(
    path: []const u8,
    local_proxy: ?ServerMeta.ProxyHandler,
    req: zx.server.Request,
    res: zx.server.Response,
    arena: std.mem.Allocator,
) ProxyResult {
    var proxy_ctx = zx.ProxyContext.init(req, res, arena, arena);
    var proxies: [16]ServerMeta.ProxyHandler = undefined;
    var count: usize = 0;

    // Root "/" proxy
    for (zx.meta.routes) |*route| {
        if (std.mem.eql(u8, route.path, "/")) {
            if (route.proxy) |proxy_fn| {
                if (count < proxies.len) {
                    proxies[count] = proxy_fn;
                    count += 1;
                }
            }
            break;
        }
    }

    // Build path segments and check each intermediate path
    var segments: [32][]const u8 = undefined;
    var seg_count: usize = 0;
    var seg_iter = std.mem.splitScalar(u8, path, '/');
    while (seg_iter.next()) |seg| {
        if (seg.len > 0 and seg_count < segments.len) {
            segments[seg_count] = seg;
            seg_count += 1;
        }
    }

    for (1..seg_count + 1) |depth| {
        var path_buf: [256]u8 = undefined;
        var offset: usize = 0;
        for (0..depth) |d| {
            path_buf[offset] = '/';
            offset += 1;
            const seg = segments[d];
            @memcpy(path_buf[offset .. offset + seg.len], seg);
            offset += seg.len;
        }
        const check_path = path_buf[0..offset];
        if (std.mem.eql(u8, check_path, "/")) continue;

        for (zx.meta.routes) |*route| {
            if (std.mem.eql(u8, route.path, check_path)) {
                if (route.proxy) |proxy_fn| {
                    if (count < proxies.len) {
                        proxies[count] = proxy_fn;
                        count += 1;
                    }
                }
                break;
            }
        }
    }

    // Execute collected proxies in order (root to leaf)
    for (proxies[0..count]) |proxy_fn| {
        proxy_fn(&proxy_ctx) catch {};
        if (proxy_ctx.isAborted()) {
            return .{ .aborted = true, .state_ptr = proxy_ctx._state_ptr };
        }
    }

    // Execute local proxy (page_proxy or route_proxy). Returns updated ProxyResult.
    if (local_proxy) |proxy_fn| {
        proxy_ctx._state_ptr = proxy_ctx._state_ptr;
        proxy_fn(&proxy_ctx) catch {};
        if (proxy_ctx.isAborted()) {
            return .{ .aborted = true, .state_ptr = proxy_ctx._state_ptr };
        }
    }

    return .{ .aborted = false, .state_ptr = proxy_ctx._state_ptr };
}

/// Registry for server actions and events (for streaming and event dispatch)
pub const ActionRegistry = struct {
    // ...implementation placeholder...
    // Add lookup, registration, and event dispatch logic as needed
};

/// Streaming support for server actions and async components
pub fn renderStreaming() void {
    // ...implementation placeholder...
    // Add streaming logic for async components, similar to server/handler.zig
}

/// Flexible handler resolution (custom HTTP methods, event handlers)
pub fn resolveCustomHandler(
    handlers: ServerMeta.RouteHandlers,
    method: zx.server.Request.Method,
    method_string: ?[]const u8,
) ?ServerMeta.RouteHandler {
    return switch (method) {
        .GET => handlers.get orelse handlers.handler,
        .POST => handlers.post orelse handlers.handler,
        .PUT => handlers.put orelse handlers.handler,
        .DELETE => handlers.delete orelse handlers.handler,
        .PATCH => handlers.patch orelse handlers.handler,
        .HEAD => handlers.head orelse handlers.handler,
        .OPTIONS => handlers.options orelse handlers.handler,
        else => blk: {
            if (handlers.custom_methods) |custom_methods| {
                if (method_string) |ms| {
                    for (custom_methods) |custom| {
                        if (std.mem.eql(u8, custom.method, ms)) {
                            break :blk custom.handler;
                        }
                    }
                }
            }
            break :blk handlers.handler;
        },
    };
}

/// Match a route by path with support for :param and * glob patterns.
/// Returns the matched route and any extracted URL parameters.
pub fn matchRoute(path: []const u8, opts: FindRouteOptions) ?RouteMatch {
    switch (opts.match) {
        .exact => {
            for (zx.meta.routes) |*route| {
                var m = RouteMatch{ .route = route };
                if (!tryExtractParams(route.path, path, &m)) continue;
                if (opts.has_notfound and route.notfound == null) continue;
                if (opts.has_error and route.@"error" == null) continue;
                return m;
            }
            return null;
        },
        .closest => {
            var current = path;
            while (true) {
                for (zx.meta.routes) |*route| {
                    var m = RouteMatch{ .route = route };
                    if (!tryExtractParams(route.path, current, &m)) continue;
                    if (opts.has_notfound and route.notfound == null) continue;
                    if (opts.has_error and route.@"error" == null) continue;
                    return m;
                }
                if (std.mem.lastIndexOfScalar(u8, current[0 .. @max(current.len, 1) - 1], '/')) |last_slash| {
                    current = if (last_slash == 0) "/" else current[0..last_slash];
                } else {
                    if (!std.mem.eql(u8, current, "/")) {
                        current = "/";
                    } else {
                        break;
                    }
                }
            }
            return null;
        },
    }
}

/// Find a route by path. Supports exact match or closest ancestor match.
/// Supports :param and * glob patterns in route paths.
pub fn findRoute(path: []const u8, opts: FindRouteOptions) ?*const Route {
    return if (matchRoute(path, opts)) |m| m.route else null;
}

/// Match a URL segment-by-segment against a route pattern.
/// Supports :name (named param) and * (glob) segments.
/// Populates match.params and match.param_count on success.
fn tryExtractParams(pattern: []const u8, path: []const u8, match: *RouteMatch) bool {
    match.param_count = 0;

    var pat = pattern;
    var url = path;

    if (pat.len > 0 and pat[0] == '/') pat = pat[1..];
    if (pat.len > 0 and pat[pat.len - 1] == '/') pat = pat[0 .. pat.len - 1];
    if (url.len > 0 and url[0] == '/') url = url[1..];
    if (url.len > 0 and url[url.len - 1] == '/') url = url[0 .. url.len - 1];

    // Both empty → root path match
    if (pat.len == 0 and url.len == 0) return true;
    if (pat.len == 0) return false;

    var pat_pos: usize = 0;
    var url_pos: usize = 0;

    while (pat_pos < pat.len) {
        const pat_end = std.mem.indexOfScalarPos(u8, pat, pat_pos, '/') orelse pat.len;
        const pseg = pat[pat_pos..pat_end];
        const is_last = (pat_end == pat.len);

        if (pseg.len == 1 and pseg[0] == '*') {
            // Trailing glob: matches everything remaining (including empty)
            if (is_last) return true;
            // Intermediate glob: matches exactly one URL segment
            if (url_pos >= url.len) return false;
            const url_end = std.mem.indexOfScalarPos(u8, url, url_pos, '/') orelse url.len;
            url_pos = url_end + 1;
            pat_pos = pat_end + 1;
            continue;
        }

        if (url_pos >= url.len) return false;
        const url_end = std.mem.indexOfScalarPos(u8, url, url_pos, '/') orelse url.len;
        const useg = url[url_pos..url_end];

        if (pseg.len > 0 and pseg[0] == ':') {
            // Named param: capture the URL segment value
            if (match.param_count < match.params.len) {
                match.params[match.param_count] = .{ .name = pseg[1..], .value = useg };
                match.param_count += 1;
            }
        } else if (!std.mem.eql(u8, pseg, useg)) {
            return false;
        }

        url_pos = url_end + 1;
        pat_pos = pat_end + 1;
    }

    // All pattern segments consumed; URL must also be fully consumed
    return url_pos >= url.len + 1;
}

/// Resolve the API route handler for a given HTTP method.
pub fn resolveRouteHandler(handlers: ServerMeta.RouteHandlers, method: zx.server.Request.Method) ?ServerMeta.RouteHandler {
    return switch (method) {
        .GET => handlers.get orelse handlers.handler,
        .POST => handlers.post orelse handlers.handler,
        .PUT => handlers.put orelse handlers.handler,
        .DELETE => handlers.delete orelse handlers.handler,
        .PATCH => handlers.patch orelse handlers.handler,
        .HEAD => handlers.head orelse handlers.handler,
        .OPTIONS => handlers.options orelse handlers.handler,
        else => handlers.handler,
    };
}

/// Execute cascading Proxy() handlers from root "/" down to the target path.
/// Does NOT execute local page_proxy/route_proxy — those are handled by the caller.
pub fn executeCascadingProxies(
    path: []const u8,
    req: zx.server.Request,
    res: zx.server.Response,
    arena: std.mem.Allocator,
) ProxyResult {
    var proxy_ctx = zx.ProxyContext.init(req, res, arena, arena);

    var proxies: [16]ServerMeta.ProxyHandler = undefined;
    var count: usize = 0;

    // Root "/" proxy
    for (zx.meta.routes) |*route| {
        if (std.mem.eql(u8, route.path, "/")) {
            if (route.proxy) |proxy_fn| {
                if (count < proxies.len) {
                    proxies[count] = proxy_fn;
                    count += 1;
                }
            }
            break;
        }
    }

    // Build path segments and check each intermediate path
    var segments: [32][]const u8 = undefined;
    var seg_count: usize = 0;
    var seg_iter = std.mem.splitScalar(u8, path, '/');
    while (seg_iter.next()) |seg| {
        if (seg.len > 0 and seg_count < segments.len) {
            segments[seg_count] = seg;
            seg_count += 1;
        }
    }

    for (1..seg_count + 1) |depth| {
        var path_buf: [256]u8 = undefined;
        var offset: usize = 0;
        for (0..depth) |d| {
            path_buf[offset] = '/';
            offset += 1;
            const seg = segments[d];
            @memcpy(path_buf[offset .. offset + seg.len], seg);
            offset += seg.len;
        }
        const check_path = path_buf[0..offset];
        if (std.mem.eql(u8, check_path, "/")) continue;

        for (zx.meta.routes) |*route| {
            if (std.mem.eql(u8, route.path, check_path)) {
                if (route.proxy) |proxy_fn| {
                    if (count < proxies.len) {
                        proxies[count] = proxy_fn;
                        count += 1;
                    }
                }
                break;
            }
        }
    }

    // Execute collected proxies in order (root to leaf)
    for (proxies[0..count]) |proxy_fn| {
        proxy_fn(&proxy_ctx) catch {};
        if (proxy_ctx.isAborted()) {
            return .{ .aborted = true, .state_ptr = proxy_ctx._state_ptr };
        }
    }

    return .{ .aborted = false, .state_ptr = proxy_ctx._state_ptr };
}

/// Execute a single local proxy (page_proxy or route_proxy). Returns updated ProxyResult.
pub fn executeLocalProxy(
    proxy_fn: ServerMeta.ProxyHandler,
    parent_result: ProxyResult,
    req: zx.server.Request,
    res: zx.server.Response,
    arena: std.mem.Allocator,
) ProxyResult {
    var proxy_ctx = zx.ProxyContext.init(req, res, arena, arena);
    proxy_ctx._state_ptr = parent_result.state_ptr;
    proxy_fn(&proxy_ctx) catch {};
    if (proxy_ctx.isAborted()) {
        return .{ .aborted = true, .state_ptr = proxy_ctx._state_ptr };
    }
    return .{ .aborted = false, .state_ptr = proxy_ctx._state_ptr };
}

/// Apply layout hierarchy for a matched route.
/// Order: route's own layout wraps the page first, then parent layouts wrap outside (leaf to root).
pub fn applyLayouts(
    route: *const Route,
    pathname: []const u8,
    layoutctx: zx.LayoutContext,
    page_component: Component,
    app_ptr: ?*const anyopaque,
    state_ptr: ?*const anyopaque,
) Component {
    var component = page_component;

    // Apply this route's own layout first
    if (route.layout) |layout_fn| {
        component = layout_fn(layoutctx, component, app_ptr, state_ptr);
    }

    // Collect parent layouts (root to deepest, excluding current route)
    var layouts: [10]ServerMeta.LayoutHandler = undefined;
    var layout_count: usize = 0;

    const is_root = std.mem.eql(u8, pathname, "/");

    // Root layout (only if current route is not root)
    if (!is_root) {
        for (zx.meta.routes) |*r| {
            if (std.mem.eql(u8, r.path, "/")) {
                if (r.layout) |layout_fn| {
                    if (layout_count < layouts.len) {
                        layouts[layout_count] = layout_fn;
                        layout_count += 1;
                    }
                }
                break;
            }
        }
    }

    // Intermediate path layouts
    var segments: [32][]const u8 = undefined;
    var seg_count: usize = 0;
    var seg_iter = std.mem.splitScalar(u8, pathname, '/');
    while (seg_iter.next()) |seg| {
        if (seg.len > 0 and seg_count < segments.len) {
            segments[seg_count] = seg;
            seg_count += 1;
        }
    }

    if (seg_count > 1) {
        for (1..seg_count) |depth| {
            var path_buf: [256]u8 = undefined;
            var offset: usize = 0;
            for (0..depth) |i| {
                path_buf[offset] = '/';
                offset += 1;
                const seg = segments[i];
                @memcpy(path_buf[offset .. offset + seg.len], seg);
                offset += seg.len;
            }
            const parent_path = path_buf[0..offset];

            // Skip if this is the current route's own path (already applied)
            if (std.mem.eql(u8, parent_path, route.path)) continue;

            for (zx.meta.routes) |*r| {
                if (std.mem.eql(u8, r.path, parent_path)) {
                    if (r.layout) |layout_fn| {
                        if (layout_count < layouts.len) {
                            layouts[layout_count] = layout_fn;
                            layout_count += 1;
                        }
                    }
                    break;
                }
            }
        }
    }

    // Apply parent layouts in reverse order (deepest parent first, root last)
    var j: usize = layout_count;
    while (j > 0) {
        j -= 1;
        component = layouts[j](layoutctx, component, app_ptr, state_ptr);
    }

    return component;
}

/// Apply layouts for an arbitrary path (used for notfound/error pages).
/// Collects all layouts from root to deepest matching ancestor.
pub fn applyLayoutsForPath(
    path: []const u8,
    layoutctx: zx.LayoutContext,
    page_component: Component,
    app_ptr: ?*const anyopaque,
    state_ptr: ?*const anyopaque,
) Component {
    var component = page_component;

    var layouts: [10]ServerMeta.LayoutHandler = undefined;
    var layout_count: usize = 0;

    // Build paths from deepest to shallowest
    var paths_to_check: [32][]const u8 = undefined;
    var path_count: usize = 0;

    if (path.len > 1) {
        paths_to_check[path_count] = path;
        path_count += 1;
    }

    var current_path = path;
    while (current_path.len > 1) {
        if (std.mem.lastIndexOfScalar(u8, current_path[0 .. current_path.len - 1], '/')) |last_slash| {
            if (last_slash == 0) {
                if (path_count < paths_to_check.len) {
                    paths_to_check[path_count] = "/";
                    path_count += 1;
                }
                break;
            } else {
                current_path = current_path[0..last_slash];
                if (path_count < paths_to_check.len) {
                    paths_to_check[path_count] = current_path;
                    path_count += 1;
                }
            }
        } else break;
    }

    if (path_count == 0 or !std.mem.eql(u8, paths_to_check[path_count - 1], "/")) {
        if (path_count < paths_to_check.len) {
            paths_to_check[path_count] = "/";
            path_count += 1;
        }
    }

    // Collect layouts from shallowest (root) to deepest (reverse iteration)
    var i: usize = path_count;
    while (i > 0) {
        i -= 1;
        if (findRoute(paths_to_check[i], .{ .match = .exact })) |r| {
            if (r.layout) |layout_fn| {
                if (layout_count < layouts.len) {
                    layouts[layout_count] = layout_fn;
                    layout_count += 1;
                }
            }
        }
    }

    // Apply in reverse (deepest first, root wraps outermost)
    var j: usize = layout_count;
    while (j > 0) {
        j -= 1;
        component = layouts[j](layoutctx, component, app_ptr, state_ptr);
    }

    return component;
}

/// Find the closest error handler and render it wrapped in layouts.
/// Returns the rendered error component, or null if no error handler found.
pub fn renderErrorComponent(
    arena: std.mem.Allocator,
    req: zx.server.Request,
    res: zx.server.Response,
    path: []const u8,
    err: anyerror,
) ?Component {
    const route = findRoute(path, .{ .match = .closest, .has_error = true }) orelse return null;
    const err_fn = route.@"error" orelse return null;

    const errorctx = zx.ErrorContext.init(req, res, arena, err);
    const layoutctx = zx.LayoutContext{
        .request = req,
        .response = res,
        .allocator = arena,
        .arena = arena,
    };

    var component = err_fn(errorctx);
    component = applyLayoutsForPath(path, layoutctx, component, null, null);
    return component;
}

/// Find the closest notfound handler and render it wrapped in layouts.
/// Returns the rendered notfound component, or null if no handler found.
pub fn renderNotFoundComponent(
    arena: std.mem.Allocator,
    req: zx.server.Request,
    res: zx.server.Response,
    path: []const u8,
    matched_route: ?*const Route,
) ?Component {
    // First try the matched route's own notfound handler
    var notfound_fn: ?*const fn (zx.NotFoundContext) Component = null;
    if (matched_route) |r| notfound_fn = r.notfound;

    // Walk up the hierarchy
    if (notfound_fn == null) {
        if (findRoute(path, .{ .match = .closest, .has_notfound = true })) |r| {
            notfound_fn = r.notfound;
        }
    }

    const nf_fn = notfound_fn orelse return null;

    const notfoundctx = zx.NotFoundContext{
        .request = req,
        .response = res,
        .allocator = arena,
        .arena = arena,
    };
    const layoutctx = zx.LayoutContext{
        .request = req,
        .response = res,
        .allocator = arena,
        .arena = arena,
    };

    var component = nf_fn(notfoundctx);
    component = applyLayoutsForPath(path, layoutctx, component, null, null);
    return component;
}
