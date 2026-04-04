const httpz = @import("httpz");
const log = std.log.scoped(.app);
const zx_injections = @import("zx_injections");
const tree = @import("../core/tree.zig");
const core_handler = @import("../core/Handler.zig");

/// ElementInjector handles injecting elements into component trees
const ElementInjector = struct {
    allocator: std.mem.Allocator,

    /// Inject a script element into the body of a component
    pub fn injectScriptIntoBody(self: ElementInjector, page: *Component, script_src: []const u8) bool {
        if (tree.getElementByName(page, self.allocator, .body)) |body_element| {
            const attributes = self.allocator.alloc(zx.Element.Attribute, 1) catch {
                std.debug.print("Error allocating attributes: OOM\n", .{});
                return false;
            };
            attributes[0] = .{ .name = "src", .value = script_src };
            const script_element = Component{ .element = .{ .tag = .script, .attributes = attributes } };
            tree.appendChild(body_element, self.allocator, script_element) catch |err| {
                std.debug.print("Error appending script to body: {}\n", .{err});
                self.allocator.free(attributes);
                return false;
            };
            return true;
        }
        return false;
    }

    pub fn injectZxInjections(self: ElementInjector, page: *Component) void {
        core_handler.injectZxInjections(self.allocator, page);
    }
};

pub const CacheConfig = struct {
    /// Maximum number of cached pages
    max_size: u32 = 1000,

    /// Default TTL in seconds for cached pages
    default_ttl: u32 = 10,
};

/// ProxyStatus tracks proxy execution for dev logging
/// Uses thread-local storage to avoid race conditions in multi-threaded server
const ProxyStatus = struct {
    threadlocal var executed: bool = false;
    threadlocal var aborted: bool = false;

    pub fn reset() void {
        executed = false;
        aborted = false;
    }

    pub fn markExecuted() void {
        executed = true;
    }

    pub fn markAborted() void {
        executed = true;
        aborted = true;
    }
};

/// Unified status indicator combining proxy and cache status
/// Format: [XY] where X=proxy status, Y=cache status
/// Position 1 (proxy): ⇥=ran, !=aborted, -=none
/// Position 2 (cache): >=hit, o=miss, -=skip
/// Brackets are dim, content is colored (non-bold for crisp rendering)
const StatusIndicator = struct {
    // Color codes (non-bold for crisp symbols)
    const dim = "\x1b[2m";
    const red = "\x1b[91m"; // bright red
    const green = "\x1b[92m"; // bright green
    const yellow = "\x1b[93m"; // bright yellow
    const magenta = "\x1b[95m"; // bright magenta
    const reset = "\x1b[0m";

    pub fn get(cache_status: PageCache.Status, http_status: u16) []const u8 {
        const proxy_ran = ProxyStatus.executed;
        const proxy_aborted = ProxyStatus.aborted;

        if (cache_status == .disabled) {
            return if (proxy_aborted)
                dim ++ "[" ++ reset ++ red ++ "!" ++ reset ++ dim ++ "-]" ++ reset ++ " "
            else if (proxy_ran)
                dim ++ "[" ++ reset ++ magenta ++ "⇥" ++ reset ++ dim ++ "-]" ++ reset ++ " "
            else
                "";
        }

        const effective_cache = if (PageCache.isCacheableHttpStatus(http_status)) cache_status else PageCache.Status.skip;

        // [XY] format: X=proxy, Y=cache (dim brackets, colored content)
        if (proxy_aborted) {
            return switch (effective_cache) {
                .hit => dim ++ "[" ++ reset ++ red ++ "!" ++ green ++ ">" ++ reset ++ dim ++ "]" ++ reset ++ " ",
                .miss => dim ++ "[" ++ reset ++ red ++ "!" ++ yellow ++ "o" ++ reset ++ dim ++ "]" ++ reset ++ " ",
                .skip => dim ++ "[" ++ reset ++ red ++ "!" ++ reset ++ dim ++ "-]" ++ reset ++ " ",
                .disabled => dim ++ "[" ++ reset ++ red ++ "!" ++ reset ++ dim ++ "-]" ++ reset ++ " ",
            };
        } else if (proxy_ran) {
            return switch (effective_cache) {
                .hit => dim ++ "[" ++ reset ++ magenta ++ "⇥" ++ green ++ ">" ++ reset ++ dim ++ "]" ++ reset ++ " ",
                .miss => dim ++ "[" ++ reset ++ magenta ++ "⇥" ++ yellow ++ "o" ++ reset ++ dim ++ "]" ++ reset ++ " ",
                .skip => dim ++ "[" ++ reset ++ magenta ++ "⇥" ++ reset ++ dim ++ "-]" ++ reset ++ " ",
                .disabled => dim ++ "[" ++ reset ++ magenta ++ "⇥" ++ reset ++ dim ++ "-]" ++ reset ++ " ",
            };
        } else {
            return switch (effective_cache) {
                .hit => dim ++ "[-" ++ reset ++ green ++ ">" ++ reset ++ dim ++ "]" ++ reset ++ " ",
                .miss => dim ++ "[-" ++ reset ++ yellow ++ "o" ++ reset ++ dim ++ "]" ++ reset ++ " ",
                .skip => dim ++ "[--]" ++ reset ++ " ",
                .disabled => "",
            };
        }
    }
};

/// PageCache handles caching of rendered HTML pages with ETag support
const PageCache = struct {
    pub const Status = enum {
        hit, // Served from cache
        miss, // Not in cache, freshly rendered
        skip, // Not cacheable (POST, internal paths, etc.)
        disabled, // Cache is disabled
    };

    const CacheValue = struct {
        body: []const u8,
        etag: []const u8,
        content_type: ?httpz.ContentType,

        pub fn removedFromCache(self: CacheValue, allocator: Allocator) void {
            allocator.free(self.body);
            allocator.free(self.etag);
        }
    };

    cache: cachez.Cache(CacheValue),
    config: CacheConfig,
    allocator: Allocator,

    pub fn init(allocator: Allocator, config: CacheConfig) !PageCache {
        return .{
            .allocator = allocator,
            .config = config,
            .cache = try cachez.Cache(CacheValue).init(allocator, .{
                .max_size = config.max_size,
            }),
        };
    }

    pub fn deinit(self: *PageCache) void {
        self.cache.deinit();
    }

    /// Try to serve from cache. Returns cache status.
    pub fn tryServe(self: *PageCache, req: *httpz.Request, res: *httpz.Response) Status {
        if (self.config.max_size == 0) return .disabled;
        if (!isCacheable(req)) return .skip;

        // Check conditional request (If-None-Match)
        if (req.header("if-none-match")) |client_etag| {
            if (self.cache.get(req.url.path)) |entry| {
                defer entry.release();
                if (std.mem.eql(u8, client_etag, entry.value.etag)) {
                    res.setStatus(.not_modified);
                    self.addCacheHeaders(res, entry.value.etag, req.arena);
                    return .hit;
                }
            }
        }

        // Try to serve full cached response
        if (self.cache.get(req.url.path)) |entry| {
            defer entry.release();
            res.content_type = entry.value.content_type;
            res.body = entry.value.body;
            self.addCacheHeaders(res, entry.value.etag, req.arena);
            return .hit;
        }

        return .miss;
    }

    /// Cache a successful response
    pub fn store(self: *PageCache, req: *httpz.Request, res: *httpz.Response) void {
        if (self.config.max_size == 0) return;
        if (!isCacheableHttpStatus(res.status)) return;
        if (!isCacheableContentType(res.content_type)) return;

        // Get response body from buffer.writer (rendered pages) or res.body (direct)
        const buffered = res.buffer.writer.buffered();
        const body = if (buffered.len > 0) buffered else res.body;
        if (body.len == 0) return;

        // Generate ETag from body hash
        const hash = std.hash.Wyhash.hash(0, body);
        const etag = std.fmt.allocPrint(self.allocator, "\"{x}\"", .{hash}) catch return;

        // Dupe the body for cache storage
        const cached_body = self.allocator.dupe(u8, body) catch {
            self.allocator.free(etag);
            return;
        };

        self.cache.put(req.url.path, .{
            .body = cached_body,
            .etag = etag,
            .content_type = res.content_type,
        }, .{
            .ttl = getTtl(req) orelse self.config.default_ttl,
        }) catch |err| {
            log.warn("Failed to cache page {s}: {}", .{ req.url.path, err });
            self.allocator.free(cached_body);
            self.allocator.free(etag);
            return;
        };

        // Add cache headers to response
        self.addCacheHeaders(res, etag, req.arena);
        res.headers.add("X-Cache", "MISS");
    }

    fn addCacheHeaders(self: *PageCache, res: *httpz.Response, etag: []const u8, arena: Allocator) void {
        res.headers.add("ETag", etag);
        res.headers.add("Cache-Control", std.fmt.allocPrint(arena, "public, max-age={d}", .{self.config.default_ttl}) catch "public, max-age=300");
        res.headers.add("X-Cache", "HIT");
    }

    fn isCacheable(req: *httpz.Request) bool {
        if (getTtl(req) == null) return false;
        if (req.method != .GET) return false;
        if (std.mem.startsWith(u8, req.url.path, "/.well-known/_zx/")) return false;
        return true;
    }

    fn isCacheableContentType(content_type: ?httpz.ContentType) bool {
        const ct = content_type orelse return false;
        return ct == .HTML or ct == .ICO or ct == .CSS or ct == .JS or ct == .TEXT;
    }
    fn isCacheableHttpStatus(http_status: u16) bool {
        return http_status == 200;
    }
    fn getTtl(req: *httpz.Request) ?u32 {
        if (req.route_data) |rd| {
            const route: *const App.Meta.Route = @ptrCast(@alignCast(rd));
            if (route.page_opts) |options| {
                // Return null if caching is disabled (seconds = 0)
                if (options.caching.seconds == 0) return null;
                return options.caching.seconds;
            }
        }
        return null;
    }

    /// Delete a specific page from the cache by exact path
    /// Example: del("/users/123")
    pub fn del(self: *PageCache, path: []const u8) bool {
        return self.cache.del(path);
    }

    /// Delete all pages matching a path prefix
    /// Example: delPath("/users") deletes /users, /users/1, /users/2, etc.
    pub fn delPath(self: *PageCache, path_prefix: []const u8) usize {
        return self.cache.delPrefix(path_prefix) catch 0;
    }
};

/// httpz backend handler.
/// Converts httpz types to abstract Request/Response, then delegates to core Handler.
/// Handles httpz-specific concerns: caching, dev logging, streaming, static files, WebSockets.
pub fn Handler(comptime AppCtxType: type) type {
    return struct {
        const Self = @This();

        meta: *App.Meta,
        config: App.Config,
        page_cache: PageCache,
        allocator: std.mem.Allocator,
        app_ctx: *AppCtxType,

        pub fn init(allocator: std.mem.Allocator, meta: *App.Meta, config: App.Config, app_ctx: *AppCtxType) !Self {
            const cache_config = config.cache;
            // Initialize unified component cache
            try zx.cache.init(allocator, .{
                .max_size = cache_config.max_size,
            });

            return Self{
                .meta = meta,
                .config = config,
                .allocator = allocator,
                .page_cache = try PageCache.init(allocator, cache_config),
                .app_ctx = app_ctx,
            };
        }

        pub fn deinit(self: *Self) void {
            self.page_cache.deinit();
        }

        pub fn dispatch(self: *Self, action: httpz.Action(*Self), req: *httpz.Request, res: *httpz.Response) !void {
            const is_dev = self.meta.cli_command == .dev;
            var timer = if (is_dev) try std.time.Timer.start() else null;

            // Reset proxy status for this request (dev mode tracking)
            if (is_dev) ProxyStatus.reset();

            // Try cache first, execute action on miss
            // Note: Middlewares are handled by httpz before this dispatch is called
            const cache_status = self.page_cache.tryServe(req, res);
            if (cache_status != .hit) {
                try action(self, req, res);
                if (cache_status == .miss) self.page_cache.store(req, res);
            }

            // Dev mode logging (skip noisy paths)
            if (is_dev and !isNoisyPath(req.url.path)) {
                const elapsed_ns = timer.?.lap();
                const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(std.time.ns_per_ms));
                const c = struct {
                    const reset_c = "\x1b[0m";
                    const method_c = "\x1b[1;34m"; // bold blue
                    const path_color = "\x1b[36m"; // cyan
                    fn time(ms: f64) []const u8 {
                        return if (ms < 10) "\x1b[92m" else if (ms < 100) "\x1b[93m" else "\x1b[91m";
                    }
                    fn status(code: u16) []const u8 {
                        return if (code < 300) "\x1b[92m" else if (code < 400) "\x1b[93m" else "\x1b[91m";
                    }
                };

                var buf: [512]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "{s}{s}{s}{s} {s}{s}{s} {s}{d}{s} {s}{d:.3}ms{s}\x1b[K", .{
                    StatusIndicator.get(cache_status, res.status),
                    c.method_c,
                    @tagName(req.method),
                    c.reset_c,
                    c.path_color,
                    req.url.path,
                    c.reset_c,
                    c.status(res.status),
                    res.status,
                    c.reset_c,
                    c.time(elapsed_ms),
                    elapsed_ms,
                    c.reset_c,
                }) catch "[log line too long]";
                std.log.info("{s}", .{msg});
            }
        }

        /// Paths to ignore in dev logging (browser probes, internal routes)
        fn isNoisyPath(path: []const u8) bool {
            if (std.mem.startsWith(u8, path, "/.well-known/")) return true;
            if (std.mem.startsWith(u8, path, "/assets/_/")) return true; // Generated assets directory
            if (std.mem.eql(u8, path, "/favicon.ico")) return true;

            return false;
        }

        pub fn notFound(self: *Self, req: *httpz.Request, res: *httpz.Response) !void {
            const path = req.url.path;

            const abstract_req = httpz_adapter.createRequest(req);
            const abstract_res = httpz_adapter.createResponse(res, req.arena);

            // Execute proxy handlers for the closest route before handling notfound
            if (zx.Router.findRoute(path, .{ .match = .closest })) |_| {
                const proxy_result = core_handler.executeNotFoundProxy(path, abstract_req, abstract_res, req.arena);
                if (proxy_result.aborted) {
                    ProxyStatus.markAborted();
                    return;
                }
                if (proxy_result.state_ptr != null) ProxyStatus.markExecuted();
            }

            res.status = 404;
            res.content_type = .HTML;

            // Delegate to core handler for not-found rendering
            const matched_route: ?*const App.Meta.Route = if (req.route_data) |rd|
                @ptrCast(@alignCast(rd))
            else
                null;

            if (core_handler.renderNotFound(path, abstract_req, abstract_res, self.allocator, matched_route)) |cmp| {
                var component = cmp;

                // Dev mode: inject dev script
                if (self.meta.cli_command == .dev) {
                    injectDevScript(req.arena, &component);
                }

                // Write to response
                res.clearWriter();
                const writer = res.writer();
                writer.writeAll("<!DOCTYPE html>\n") catch {
                    res.body = "404 Not Found";
                    return;
                };
                component.render(writer) catch {
                    res.body = "404 Not Found";
                };
            } else {
                res.body = "404 Not Found";
            }
        }

        pub fn uncaughtError(self: *Self, req: *httpz.Request, res: *httpz.Response, err: anyerror) void {
            const path = req.url.path;

            res.status = 500;
            res.content_type = .HTML;

            const abstract_req = httpz_adapter.createRequest(req);
            const abstract_res = httpz_adapter.createResponse(res, req.arena);

            // Delegate to core handler for error rendering
            if (core_handler.renderError(path, abstract_req, abstract_res, self.allocator, err)) |cmp| {
                var component = cmp;

                // Dev mode: inject dev script
                if (self.meta.cli_command == .dev) {
                    injectDevScript(req.arena, &component);
                }

                // Write to response
                res.clearWriter();
                const writer = res.writer();
                writer.writeAll("<!DOCTYPE html>\n") catch {
                    res.body = "500 Internal Server Error";
                    return;
                };
                component.render(writer) catch {
                    res.body = "500 Internal Server Error";
                };
            } else {
                res.body = "500 Internal Server Error";
            }
        }

        fn injectDevScript(arena: Allocator, component: *Component) void {
            const inj = ElementInjector{ .allocator = arena };
            _ = inj.injectScriptIntoBody(component, "/.well-known/_zx/devscript.js");
        }

        pub fn api(self: *Self, req: *httpz.Request, res: *httpz.Response) !void {
            const allocator = self.allocator;
            const abstract_req = httpz_adapter.createRequest(req);
            const abstract_res = httpz_adapter.createResponse(res, req.arena);

            // Get route data
            const route_data: *const App.Meta.Route = if (req.route_data) |rd|
                @ptrCast(@alignCast(rd))
            else
                return self.notFound(req, res);

            // Execute proxy via core handler
            const proxy_result = core_handler.executeRouteProxy(route_data, abstract_req, abstract_res, req.arena);
            if (proxy_result.aborted) {
                ProxyStatus.markAborted();
                return;
            }
            if (proxy_result.state_ptr != null) ProxyStatus.markExecuted();

            const handlers = route_data.route orelse return self.notFound(req, res);

            // Check if this route has a Socket handler and might want to upgrade
            if (handlers.socket) |socket_handler| {
                // Create upgrade context for socket operations
                var upgrade_ctx = httpz_adapter.SocketUpgradeContext{
                    .allocator = allocator,
                    .req = req,
                    .res = res,
                };
                const socket = httpz_adapter.createUpgradeSocket(&upgrade_ctx);

                // Delegate to core handler
                const result = core_handler.handleApi(
                    route_data,
                    abstract_req,
                    abstract_res,
                    allocator,
                    self.app_ctx,
                    proxy_result.state_ptr,
                    socket,
                );

                switch (result) {
                    .not_found => return self.notFound(req, res),
                    .handler_error => |err| return self.uncaughtError(req, res, err),
                    .handled => {},
                }

                // If the handler called socket.upgrade(), perform the actual WebSocket upgrade
                if (upgrade_ctx.upgraded) {
                    const ws_ctx = WebsocketContext{
                        .socket_handler = socket_handler,
                        .socket_open_handler = handlers.socket_open,
                        .socket_close_handler = handlers.socket_close,
                        .allocator = allocator,
                        .upgrade_data = upgrade_ctx.upgrade_data,
                    };
                    if (try httpz.upgradeWebsocket(WebsocketHandler, req, res, ws_ctx) == false) {
                        res.status = 400;
                        res.body = "Invalid WebSocket handshake";
                    }
                }
            } else {
                // No socket handler, use regular route context
                const result = core_handler.handleApi(
                    route_data,
                    abstract_req,
                    abstract_res,
                    allocator,
                    self.app_ctx,
                    proxy_result.state_ptr,
                    .{}, // empty socket
                );

                switch (result) {
                    .not_found => return self.notFound(req, res),
                    .handler_error => |err| return self.uncaughtError(req, res, err),
                    .handled => {},
                }
            }
        }

        pub fn page(self: *Self, req: *httpz.Request, res: *httpz.Response) !void {
            const allocator = self.allocator;
            const is_dev_mode = self.meta.cli_command == .dev;
            const is_export_mode = self.meta.cli_command == .@"export";

            if (is_export_mode) {
                if (req.header("x-zx-export-notfound")) |_| {
                    return self.notFound(req, res);
                }

                // Handle static params request for dynamic routes
                if (req.header("x-zx-static-data")) |_| {
                    if (req.route_data) |rd| {
                        const route: *const App.Meta.Route = @ptrCast(@alignCast(rd));
                        if (route.page_opts) |page_opts| {
                            if (page_opts.static) |static_opts| {
                                const params = try self.resolveStaticParams(req.arena, static_opts);
                                try std.zon.stringify.serialize(params, .{ .whitespace = true }, res.writer());
                            }
                        }
                    }
                    return;
                }
            }

            const abstract_req = httpz_adapter.createRequest(req);
            const abstract_res = httpz_adapter.createResponse(res, req.arena);

            // Get route data
            const route: *const App.Meta.Route = if (req.route_data) |rd|
                @ptrCast(@alignCast(rd))
            else
                return self.notFound(req, res);

            // Execute proxy via core handler
            const proxy_result = core_handler.executePageProxy(route, abstract_req, abstract_res, req.arena);
            if (proxy_result.aborted) {
                ProxyStatus.markAborted();
                return;
            }
            if (proxy_result.state_ptr != null) ProxyStatus.markExecuted();

            // Delegate to core handler for page handling
            const result = try core_handler.handlePage(
                route,
                abstract_req,
                abstract_res,
                allocator,
                req.arena,
                self.app_ctx,
                proxy_result.state_ptr,
            );

            switch (result) {
                .component => |cmp| {
                    var page_component = cmp;

                    // Dev mode: inject dev script
                    if (is_dev_mode) {
                        injectDevScript(req.arena, &page_component);
                    }

                    // Handle devtool request
                    const is_devtool = is_dev_mode and std.mem.eql(u8, req.url.path, "/.well-known/_zx/devtool");
                    if (is_devtool) {
                        const query = try req.query();
                        const include_native = !std.mem.eql(u8, query.get("include_native") orelse "1", "0");
                        res.content_type = .JSON;
                        try page_component.formatWithOptions(res.writer(), .{ .only_components = !include_native });
                        return;
                    }

                    // Check if streaming is enabled
                    if (core_handler.isStreamingEnabled(route)) {
                        try self.renderStreaming(res, &page_component, req.arena);
                    } else {
                        // Normal mode: render everything at once
                        const writer = &res.buffer.writer;
                        _ = writer.write("<!DOCTYPE html>\n") catch |err| {
                            std.debug.print("Error writing HTML: {}\n", .{err});
                            return;
                        };
                        page_component.render(writer) catch |err| {
                            std.debug.print("Error rendering page: {}\n", .{err});
                            return self.uncaughtError(req, res, err);
                        };
                    }

                    res.content_type = .HTML;
                },
                .action_handled => |r| {
                    if (r.body) |body| {
                        res.content_type = .JSON;
                        res.body = body;
                    }
                },
                .action_native => {
                    // Action was invoked natively (form POST), re-render the page
                    // Re-delegate to get the rendered component
                    const re_result = try core_handler.handlePage(
                        route,
                        abstract_req,
                        abstract_res,
                        allocator,
                        req.arena,
                        self.app_ctx,
                        proxy_result.state_ptr,
                    );
                    switch (re_result) {
                        .component => |cmp| {
                            var page_component = cmp;
                            if (is_dev_mode) injectDevScript(req.arena, &page_component);
                            const writer = &res.buffer.writer;
                            _ = writer.write("<!DOCTYPE html>\n") catch return;
                            page_component.render(writer) catch |err| return self.uncaughtError(req, res, err);
                            res.content_type = .HTML;
                        },
                        .page_error => |err| return self.uncaughtError(req, res, err),
                        .not_found => return self.notFound(req, res),
                        else => {},
                    }
                },
                .event_handled => |r| {
                    res.content_type = .JSON;
                    res.body = r.body orelse "{}";
                },
                .not_found => return self.notFound(req, res),
                .page_error => |err| return self.uncaughtError(req, res, err),
                .action_not_found => {
                    res.status = 400;
                    res.body = "No action handler registered for this route";
                },
                .event_not_found => {
                    res.status = 400;
                    res.body = "No server event handler registered for this route";
                },
            }
        }

        // TODO: Move to DevServer
        pub fn devtool(self: *Self, req: *httpz.Request, res: *httpz.Response) !void {
            // Add cors headers
            res.header("Access-Control-Allow-Origin", "*");
            res.header("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
            res.header("Access-Control-Allow-Headers", "Content-Type");
            if (req.method == .OPTIONS) {
                res.status = 200;
                return;
            }

            const query = try req.query();
            const is_meta = query.get("meta") != null;
            if (is_meta) {
                const meta_data = try zx.server.SerilizableAppMeta.init(req.arena, self.meta, self.config.server);
                res.content_type = .JSON;
                try meta_data.serializeRoutes(res.writer());
                return;
            }
            const target_path = query.get("path") orelse "/";

            if (zx.Router.findRoute(target_path, .{ .match = .exact })) |route| {
                req.route_data = @constCast(route);
                return self.page(req, res);
            } else {
                return self.notFound(req, res);
            }
        }

        fn resolveStaticParams(self: *Self, allocator_arg: Allocator, static_opts: zx.PageOptions.Static) ![]const []const zx.PageOptions.StaticParam {
            _ = self;
            var params = std.ArrayList([]const zx.PageOptions.StaticParam).empty;
            if (static_opts.params) |p| {
                try params.appendSlice(allocator_arg, p);
            }

            if (static_opts.getParams) |getter| {
                const p = try getter(allocator_arg);
                try params.appendSlice(allocator_arg, p);
            }

            return try params.toOwnedSlice(allocator_arg);
        }

        /// Render a page with streaming SSR support
        /// Sends the initial shell immediately, then streams async components as they complete
        fn renderStreaming(self: *Self, res: *httpz.Response, page_component: *Component, arena: std.mem.Allocator) !void {
            _ = self;

            var shell_writer = std.Io.Writer.Allocating.init(arena);
            const async_components = rndr.stream(page_component.*, arena, &shell_writer.writer) catch |err| {
                std.debug.print("Error streaming page: {}\n", .{err});
                return err;
            };

            res.chunk("<!DOCTYPE html>\n") catch |err| {
                std.debug.print("Error sending DOCTYPE: {}\n", .{err});
                return err;
            };
            res.chunk(shell_writer.written()) catch |err| {
                std.debug.print("Error sending shell: {}\n", .{err});
                return err;
            };

            if (async_components.len > 0) {
                res.chunk(rndr.streaming_bootstrap_script) catch |err| {
                    std.debug.print("Error sending bootstrap script: {}\n", .{err});
                    return err;
                };
                const AsyncResult = struct {
                    script: []const u8 = &.{},
                    done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
                };

                const results = std.heap.page_allocator.alloc(AsyncResult, async_components.len) catch |err| {
                    std.debug.print("Error allocating results: {}\n", .{err});
                    return err;
                };
                defer std.heap.page_allocator.free(results);

                for (results) |*result_entry| {
                    result_entry.* = .{};
                }

                var remaining = std.atomic.Value(usize).init(async_components.len);

                const TaskContext = struct {
                    async_comp: rndr.AsyncComponent,
                    result: *AsyncResult,
                    remaining_ref: *std.atomic.Value(usize),

                    fn work(ctx: *@This()) void {
                        defer {
                            _ = ctx.remaining_ref.fetchSub(1, .seq_cst);
                            std.heap.page_allocator.destroy(ctx);
                        }

                        const script = ctx.async_comp.renderScript(std.heap.page_allocator) catch |work_err| {
                            std.debug.print("Error rendering async component {d}: {}\n", .{ ctx.async_comp.id, work_err });
                            ctx.result.done.store(true, .seq_cst);
                            return;
                        };

                        ctx.result.script = script;
                        ctx.result.done.store(true, .seq_cst);
                    }
                };

                var threads = std.heap.page_allocator.alloc(?std.Thread, async_components.len) catch |err| {
                    std.debug.print("Error allocating threads: {}\n", .{err});
                    return err;
                };
                defer std.heap.page_allocator.free(threads);

                for (async_components, 0..) |async_comp, i| {
                    const ctx = std.heap.page_allocator.create(TaskContext) catch {
                        threads[i] = null;
                        continue;
                    };
                    ctx.* = .{
                        .async_comp = async_comp,
                        .result = &results[i],
                        .remaining_ref = &remaining,
                    };

                    threads[i] = std.Thread.spawn(.{}, TaskContext.work, .{ctx}) catch blk: {
                        std.heap.page_allocator.destroy(ctx);
                        _ = remaining.fetchSub(1, .seq_cst);
                        results[i].done.store(true, .seq_cst);
                        break :blk null;
                    };
                }

                var streamed = std.heap.page_allocator.alloc(bool, async_components.len) catch |err| {
                    std.debug.print("Error allocating streamed flags: {}\n", .{err});
                    return err;
                };
                defer std.heap.page_allocator.free(streamed);
                @memset(streamed, false);

                var completed: usize = 0;
                var connection_closed = false;
                while (completed < async_components.len and !connection_closed) {
                    for (results, 0..) |*result_entry, i| {
                        if (streamed[i]) continue;

                        if (result_entry.done.load(.seq_cst)) {
                            if (result_entry.script.len > 0) {
                                res.chunk(result_entry.script) catch |chunk_err| {
                                    std.debug.print("Error streaming async component: {}\n", .{chunk_err});
                                    connection_closed = true;
                                    break;
                                };
                            }
                            streamed[i] = true;
                            completed += 1;
                        }
                    }
                    if (completed < async_components.len and !connection_closed) {
                        std.Thread.sleep(5 * std.time.ns_per_ms);
                    }
                }

                for (threads) |maybe_thread| {
                    if (maybe_thread) |thread| {
                        thread.join();
                    }
                }
            }
        }

        pub fn assets(self: *Self, req: *httpz.Request, res: *httpz.Response) !void {
            try self.static(req, res);
        }
        pub fn public(self: *Self, req: *httpz.Request, res: *httpz.Response) !void {
            try self.static(req, res);
        }

        pub inline fn static(self: *Self, req: *httpz.Request, res: *httpz.Response) !void {
            const allocator_s = self.allocator;

            const rootdir = self.meta.rootdir orelse zx_options.staticdir;
            const assets_path = try std.fs.path.join(allocator_s, &.{ rootdir, req.url.path });
            defer allocator_s.free(assets_path);

            const body = std.fs.cwd().readFileAlloc(allocator_s, assets_path, std.math.maxInt(usize)) catch |err| {
                switch (err) {
                    error.FileNotFound => return self.notFound(req, res),
                    else => return self.uncaughtError(req, res, err),
                }
            };

            res.body = body;
            res.content_type = httpz.ContentType.forFile(req.url.path);
        }

        /// Context passed when upgrading to WebSocket
        /// Contains the socket handler functions and allocator
        pub const WebsocketContext = struct {
            socket_handler: ?App.Meta.SocketHandler = null,
            socket_open_handler: ?App.Meta.SocketOpenHandler = null,
            socket_close_handler: ?App.Meta.SocketCloseHandler = null,
            allocator: std.mem.Allocator = std.heap.page_allocator,
            /// Copied user data bytes passed during upgrade
            upgrade_data: ?[]const u8 = null,
        };

        pub const WebsocketHandler = struct {
            conn: *httpz.websocket.Conn,
            socket_handler: ?App.Meta.SocketHandler,
            socket_open_handler: ?App.Meta.SocketOpenHandler,
            socket_close_handler: ?App.Meta.SocketCloseHandler,
            ws_allocator: std.mem.Allocator,
            upgrade_data: ?[]const u8,
            /// Subscriber data for pub/sub (stored directly on connection)
            subscriber: pubsub.SubscriberData,

            pub fn init(conn: *httpz.websocket.Conn, ctx: WebsocketContext) !WebsocketHandler {
                return .{
                    .conn = conn,
                    .socket_handler = ctx.socket_handler,
                    .socket_open_handler = ctx.socket_open_handler,
                    .socket_close_handler = ctx.socket_close_handler,
                    .ws_allocator = ctx.allocator,
                    .upgrade_data = ctx.upgrade_data,
                    .subscriber = pubsub.SubscriberData.init(conn, ctx.allocator),
                };
            }

            /// Called after the WebSocket connection is established
            pub fn afterInit(self: *WebsocketHandler) !void {
                if (self.socket_open_handler) |handler| {
                    const socket = self.createSocket();
                    handler(socket, self.upgrade_data, self.ws_allocator, self.ws_allocator) catch |err| {
                        log.err("SocketOpen handler error: {}", .{err});
                    };
                }
            }

            /// Called when a text or binary message is received from the client
            pub fn clientMessage(self: *WebsocketHandler, _: Allocator, data: []const u8, message_type: httpz.websocket.MessageTextType) !void {
                const msg_type: zx.SocketMessageType = switch (message_type) {
                    .text => .text,
                    .binary => .binary,
                };

                if (self.socket_handler) |handler| {
                    const socket = self.createSocket();
                    handler(socket, data, msg_type, self.upgrade_data, self.ws_allocator, self.ws_allocator) catch |err| {
                        log.err("Socket handler error: {}", .{err});
                    };
                } else {
                    // Default echo behavior when no handler defined
                    try self.conn.write(data);
                }
            }

            /// Called when the connection is being closed (for any reason)
            pub fn close(self: *WebsocketHandler) void {
                // Unsubscribe from all topics (pub/sub cleanup)
                self.subscriber.unsubscribeAll();

                if (self.socket_close_handler) |handler| {
                    const socket = self.createSocket();
                    handler(socket, self.upgrade_data, self.ws_allocator);
                }

                // Free the upgrade_data that was allocated with page_allocator during upgrade
                if (self.upgrade_data) |data| {
                    std.heap.page_allocator.free(data);
                }
            }

            /// Create a Socket interface for the current connection
            fn createSocket(self: *WebsocketHandler) zx.Socket {
                return zx.Socket{
                    .backend_ctx = @ptrCast(self),
                    .vtable = &socket_vtable,
                };
            }

            const socket_vtable = zx.Socket.VTable{
                .upgrade = &socketUpgrade,
                .upgradeWithData = &socketUpgradeWithData,
                .write = &socketWrite,
                .read = &socketRead,
                .close = &socketClose,
                .subscribe = &socketSubscribe,
                .unsubscribe = &socketUnsubscribe,
                .publish = &socketPublish,
                .isSubscribed = &socketIsSubscribed,
                .setPublishToSelf = &socketSetPublishToSelf,
            };

            fn socketUpgrade(_: *anyopaque) anyerror!void {
                return error.WebSocketAlreadyConnected;
            }

            fn socketUpgradeWithData(_: *anyopaque, _: []const u8) anyerror!void {
                return error.WebSocketAlreadyConnected;
            }

            fn socketWrite(ctx: *anyopaque, data: []const u8) anyerror!void {
                const handler: *WebsocketHandler = @ptrCast(@alignCast(ctx));
                try handler.conn.write(data);
            }

            fn socketRead(_: *anyopaque) ?[]const u8 {
                return null;
            }

            fn socketClose(ctx: *anyopaque) void {
                const handler: *WebsocketHandler = @ptrCast(@alignCast(ctx));
                handler.conn.close(.{ .code = 1000, .reason = "closed" }) catch {};
            }

            // Pub/Sub vtable implementations - use subscriber data stored on connection
            fn socketSubscribe(ctx: *anyopaque, topic: []const u8) void {
                const handler: *WebsocketHandler = @ptrCast(@alignCast(ctx));
                handler.subscriber.subscribe(topic);
            }

            fn socketUnsubscribe(ctx: *anyopaque, topic: []const u8) void {
                const handler: *WebsocketHandler = @ptrCast(@alignCast(ctx));
                handler.subscriber.unsubscribe(topic);
            }

            fn socketPublish(ctx: *anyopaque, topic: []const u8, message: []const u8) usize {
                const handler: *WebsocketHandler = @ptrCast(@alignCast(ctx));
                return pubsub.getPubSub().publish(&handler.subscriber, topic, message);
            }

            fn socketIsSubscribed(ctx: *anyopaque, topic: []const u8) bool {
                const handler: *WebsocketHandler = @ptrCast(@alignCast(ctx));
                return handler.subscriber.isSubscribed(topic);
            }

            fn socketSetPublishToSelf(ctx: *anyopaque, value: bool) void {
                const handler: *WebsocketHandler = @ptrCast(@alignCast(ctx));
                handler.subscriber.publish_to_self = value;
            }
        };
    };
}

const std = @import("std");
const builtin = @import("builtin");
const cachez = @import("cachez");

const zx_options = @import("zx_options");
const zx = @import("../../root.zig");
const httpz_adapter = @import("adapter.zig");
const pubsub = @import("pubsub.zig");
const rndr = @import("render.zig");
const ctxs = @import("../../contexts.zig");
const Allocator = std.mem.Allocator;
const Component = zx.Component;
const App = zx.Server(void);
const Request = @import("../core/Request.zig");
const Response = @import("../core/Response.zig");
