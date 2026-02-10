const httpz = @import("httpz");
const module_config = @import("zx_info");
const log = std.log.scoped(.app);

/// ElementInjector handles injecting elements into component trees
const ElementInjector = struct {
    allocator: std.mem.Allocator,

    /// Inject a script element into the body of a component
    /// Returns true if injection was successful, false if body element not found
    pub fn injectScriptIntoBody(self: ElementInjector, page: *Component, script_src: []const u8) bool {
        if (page.getElementByName(self.allocator, .body)) |body_element| {
            // Allocate attributes array properly (not a pointer to stack memory)
            const attributes = self.allocator.alloc(zx.Element.Attribute, 1) catch {
                std.debug.print("Error allocating attributes: OOM\n", .{});
                return false;
            };
            attributes[0] = .{
                .name = "src",
                .value = script_src,
            };

            const script_element = Component{
                .element = .{
                    .tag = .script,
                    .attributes = attributes,
                },
            };

            body_element.appendChild(self.allocator, script_element) catch |err| {
                std.debug.print("Error appending script to body: {}\n", .{err});
                self.allocator.free(attributes);
                return false;
            };
            return true;
        }
        return false;
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

/// Generic Handler that stores application context and injects it into page/layout contexts.
/// The AppCtxType is the type of your application context struct.
pub fn Handler(comptime AppCtxType: type) type {
    return struct {
        const Self = @This();

        meta: *App.Meta,
        page_cache: PageCache,
        allocator: std.mem.Allocator,
        app_ctx: *AppCtxType,

        pub fn init(allocator: std.mem.Allocator, meta: *App.Meta, cache_config: CacheConfig, app_ctx: *AppCtxType) !Self {
            // Initialize unified component cache
            try zx.cache.init(allocator, .{
                .max_size = cache_config.max_size,
            });

            return Self{
                .meta = meta,
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
                    const reset = "\x1b[0m";
                    const method = "\x1b[1;34m"; // bold blue
                    const path_color = "\x1b[36m"; // cyan
                    fn time(ms: f64) []const u8 {
                        return if (ms < 10) "\x1b[92m" else if (ms < 100) "\x1b[93m" else "\x1b[91m";
                    }
                    fn status(code: u16) []const u8 {
                        return if (code < 300) "\x1b[92m" else if (code < 400) "\x1b[93m" else "\x1b[91m";
                    }
                };

                std.log.info("{s}{s}{s}{s} {s}{s}{s} {s}{d}{s} {s}{d:.3}ms{s}\x1b[K", .{
                    StatusIndicator.get(cache_status, res.status),
                    c.method,
                    @tagName(req.method),
                    c.reset,
                    c.path_color,
                    req.url.path,
                    c.reset,
                    c.status(res.status),
                    res.status,
                    c.reset,
                    c.time(elapsed_ms),
                    elapsed_ms,
                    c.reset,
                });
            }
        }

        /// Paths to ignore in dev logging (browser probes, internal routes)
        fn isNoisyPath(path: []const u8) bool {
            return std.mem.startsWith(u8, path, "/.well-known/") or
                std.mem.eql(u8, path, "/favicon.ico");
        }

        pub fn notFound(self: *Self, req: *httpz.Request, res: *httpz.Response) !void {
            const path = req.url.path;

            const abstract_req = httpz_adapter.createRequest(req);
            const abstract_res = httpz_adapter.createResponse(res, req.arena);

            // Execute proxy handlers for the closest route before handling notfound
            // This allows auth/logging proxies to run even for 404 pages
            if (self.findRoute(path, .{ .match = .closest })) |route| {
                const proxy_result = try self.executeNotFoundProxy(route, path, abstract_req, abstract_res, req.arena);
                if (proxy_result.aborted) {
                    // Proxy handled the request, don't continue
                    return;
                }
            }

            res.status = 404;
            res.content_type = .HTML;

            const notfoundctx = zx.NotFoundContext.init(abstract_req, abstract_res, self.allocator);

            // First try to get notfound from route_data if available
            var notfound_fn: ?*const fn (zx.NotFoundContext) Component = null;
            if (req.route_data) |rd| {
                const route: *const App.Meta.Route = @ptrCast(@alignCast(rd));
                notfound_fn = route.notfound;
            }

            // If no notfound from route_data, find the closest route with notfound handler
            if (notfound_fn == null) {
                if (self.findRoute(path, .{ .match = .closest, .has_notfound = true })) |route| {
                    notfound_fn = route.notfound;
                }
            }

            // If still no notfound handler found, return plain error
            const nf_fn = notfound_fn orelse {
                res.body = "404 Not Found";
                return;
            };

            // Render the notfound component wrapped in layouts
            const notfound_cmp = nf_fn(notfoundctx);
            res.clearWriter();
            self.renderErrorPage(req, res, notfound_cmp, .{
                .fallback_message = "Internal Server Error, notfound page rendering failed",
            });
        }

        pub fn uncaughtError(self: *Self, req: *httpz.Request, res: *httpz.Response, err: anyerror) void {
            const path = req.url.path;

            res.status = 500;
            res.content_type = .HTML;

            const abstract_req = httpz_adapter.createRequest(req);
            const abstract_res = httpz_adapter.createResponse(res, req.arena);
            const errorctx = zx.ErrorContext.init(abstract_req, abstract_res, self.allocator, err);

            // Find the closest route with error handler
            var error_fn: ?*const fn (zx.ErrorContext) Component = null;
            if (self.findRoute(path, .{ .match = .closest, .has_error = true })) |route| {
                error_fn = route.@"error";
            }

            // If no error handler found, return plain error
            const err_fn = error_fn orelse {
                res.body = "500 Internal Server Error";
                return;
            };

            // Render the error component wrapped in layouts
            const error_cmp = err_fn(errorctx);
            res.clearWriter();
            self.renderErrorPage(req, res, error_cmp, .{
                .fallback_message = "Internal Server Error, error page rendering failed",
            });
        }

        const RenderErrorPageOptions = struct {
            fallback_message: []const u8 = "Internal Server Error",
        };

        const InjectScriptsOptions = struct {
            dev: bool = false,
            jsglue: bool = false,
        };

        fn injectScripts(arena: Allocator, component: *Component, comptime opts: InjectScriptsOptions) void {
            const inj = ElementInjector{ .allocator = arena };

            if (opts.dev) _ = inj.injectScriptIntoBody(component, "/.well-known/_zx/devscript.js");
            if (opts.jsglue) {
                const jsglue_cdn_href =
                    std.fmt.comptimePrint("https://cdn.jsdelivr.net/npm/ziex@{s}/wasm/init.min.js", .{module_config.jsglue_version});
                const jsglue_href = if (zx_options.jsglue_href) |href| href else jsglue_cdn_href;

                _ = inj.injectScriptIntoBody(component, jsglue_href);
            }
        }

        /// Shared method to render error/notfound pages wrapped in parent layouts
        fn renderErrorPage(
            self: *Self,
            req: *httpz.Request,
            res: *httpz.Response,
            page_component: Component,
            opts: RenderErrorPageOptions,
        ) void {
            const path = req.url.path;
            const abstract_req = httpz_adapter.createRequest(req);
            const abstract_res = httpz_adapter.createResponse(res, req.arena);
            const layoutctx = zx.LayoutContext.initWithAppPtr(self.app_ctx, abstract_req, abstract_res, self.allocator);
            const is_dev_mode = self.meta.cli_command == .dev;

            var component = page_component;

            // Collect all parent layouts from root to deepest
            var layouts_to_apply: [10]App.Meta.LayoutHandler = undefined;
            var layouts_count: usize = 0;

            // Build list of paths from deepest to shallowest
            var paths_to_check: [32][]const u8 = undefined;
            var path_count: usize = 0;

            // First, include the current path itself (if it's not just "/")
            if (path.len > 1) {
                paths_to_check[path_count] = path;
                path_count += 1;
            }

            // Build parent paths by removing trailing segments (deepest to shallowest)
            var current_path = path;
            while (current_path.len > 1) {
                if (std.mem.lastIndexOfScalar(u8, current_path[0 .. current_path.len - 1], '/')) |last_slash| {
                    if (last_slash == 0) {
                        paths_to_check[path_count] = "/";
                        path_count += 1;
                        break;
                    } else {
                        current_path = current_path[0..last_slash];
                        paths_to_check[path_count] = current_path;
                        path_count += 1;
                    }
                } else {
                    break;
                }
            }

            // Ensure root "/" is included if not already
            if (path_count == 0 or !std.mem.eql(u8, paths_to_check[path_count - 1], "/")) {
                paths_to_check[path_count] = "/";
                path_count += 1;
            }

            // Collect layouts from shallowest (root) to deepest
            // We iterate in reverse since paths_to_check is ordered deepest to shallowest
            var i: usize = path_count;
            while (i > 0) {
                i -= 1;
                if (self.findRoute(paths_to_check[i], .{ .match = .exact })) |route| {
                    if (route.layout) |layout_fn| {
                        if (layouts_count < layouts_to_apply.len) {
                            layouts_to_apply[layouts_count] = layout_fn;
                            layouts_count += 1;
                        }
                    }
                }
            }

            // Apply layouts in reverse order (deepest first, then parent layouts wrap around)
            // This means root layout is applied last, wrapping everything
            var injector: ?ElementInjector = null;
            if (is_dev_mode) {
                injector = ElementInjector{ .allocator = req.arena };
            }

            var j: usize = layouts_count;
            while (j > 0) {
                j -= 1;
                component = layouts_to_apply[j](layoutctx, component);
                // In dev mode, inject dev script into body element of root layout (last one applied, j == 0)
                if (j == 0 and injector != null) {
                    injectScripts(req.arena, &component, .{ .dev = true });
                    injector = null;
                }
            }

            // If no layouts were applied but we're in dev mode, still try to inject
            if (layouts_count == 0 and is_dev_mode) {
                injectScripts(req.arena, &component, .{ .dev = true });
            }

            if (comptime zx_options.client_enabled) {
                injectScripts(req.arena, &component, .{ .jsglue = true });
            }

            // Render the final component
            const writer = res.writer();
            writer.writeAll("<!DOCTYPE html>\n") catch {
                res.body = opts.fallback_message;
                return;
            };
            component.render(writer) catch {
                res.body = opts.fallback_message;
            };
        }

        const FindRouteOptions = struct {
            match: enum { closest, exact } = .exact,
            has_notfound: bool = false,
            has_error: bool = false,
            has_layout: bool = false,
            has_page_opts: bool = false,
            has_layout_opts: bool = false,
            has_notfound_opts: bool = false,
            has_error_opts: bool = false,
        };

        pub fn findRoute(
            self: *Self,
            path: []const u8,
            opts: FindRouteOptions,
        ) ?*const App.Meta.Route {
            switch (opts.match) {
                .closest => {
                    // For closest match, we want to find the deepest route that matches
                    // by building up the path progressively from root to leaf.
                    // E.g., for "/users/profile/settings", check:
                    // "/users/profile/settings", then "/users/profile", then "/users", then "/"
                    // Return the first (deepest) match that has the required handlers.

                    const no_filters =
                        !opts.has_layout and
                        !opts.has_notfound and
                        !opts.has_error and
                        !opts.has_page_opts and
                        !opts.has_layout_opts and
                        !opts.has_notfound_opts and
                        !opts.has_error_opts;

                    // Build list of paths to check from deepest to shallowest
                    var paths_to_check: [32][]const u8 = undefined;
                    var path_count: usize = 0;

                    // Start with the full path
                    if (path.len > 0) {
                        paths_to_check[path_count] = path;
                        path_count += 1;
                    }

                    // Build parent paths by removing trailing segments
                    var current_path = path;
                    while (current_path.len > 1) {
                        // Find the last '/' and truncate
                        if (std.mem.lastIndexOfScalar(u8, current_path[0 .. current_path.len - 1], '/')) |last_slash| {
                            if (last_slash == 0) {
                                // Parent is root "/"
                                paths_to_check[path_count] = "/";
                                path_count += 1;
                                break;
                            } else {
                                current_path = current_path[0..last_slash];
                                paths_to_check[path_count] = current_path;
                                path_count += 1;
                            }
                        } else {
                            break;
                        }
                    }

                    // Ensure root "/" is included if not already
                    if (path_count == 0 or !std.mem.eql(u8, paths_to_check[path_count - 1], "/")) {
                        paths_to_check[path_count] = "/";
                        path_count += 1;
                    }

                    // Check paths from deepest to shallowest
                    for (paths_to_check[0..path_count]) |check_path| {
                        if (self.findRoute(check_path, .{ .match = .exact })) |route| {
                            // If no filters specified, return first match
                            if (no_filters) {
                                return route;
                            }

                            // Check if route matches any of the requested filters
                            const matches_filter =
                                (opts.has_layout and route.layout != null) or
                                (opts.has_notfound and route.notfound != null) or
                                (opts.has_error and route.@"error" != null) or
                                (opts.has_page_opts and route.page_opts != null) or
                                (opts.has_layout_opts and route.layout_opts != null) or
                                (opts.has_notfound_opts and route.notfound_opts != null) or
                                (opts.has_error_opts and route.error_opts != null);

                            if (matches_filter) {
                                return route;
                            }
                        }
                    }

                    return null;
                },
                .exact => {
                    for (self.meta.routes) |*route| {
                        if (std.mem.eql(u8, route.path, path)) {
                            return route;
                        }
                    }
                },
            }
            return null;
        }

        /// Collect all cascading Proxy() handlers from root to the given path
        /// Returns the count of handlers collected
        fn collectCascadingProxies(self: *Self, path: []const u8, proxies: *[16]App.Meta.ProxyHandler, arena: std.mem.Allocator) usize {
            var count: usize = 0;

            // Build path segments to traverse
            var path_segments = std.array_list.Managed([]const u8).init(arena);
            defer path_segments.deinit();
            var path_iter = std.mem.splitScalar(u8, path, '/');
            while (path_iter.next()) |segment| {
                if (segment.len > 0) {
                    path_segments.append(segment) catch break;
                }
            }

            // First check root path "/" for proxy
            for (self.meta.routes) |*route| {
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

            // Traverse from root to target path, collecting Proxy() handlers
            for (1..path_segments.items.len + 1) |depth| {
                var path_buf: [256]u8 = undefined;
                var offset: usize = 0;
                for (0..depth) |d| {
                    path_buf[offset] = '/';
                    offset += 1;
                    const seg = path_segments.items[d];
                    @memcpy(path_buf[offset .. offset + seg.len], seg);
                    offset += seg.len;
                }
                const check_path = path_buf[0..offset];

                // Skip root (already handled)
                if (std.mem.eql(u8, check_path, "/")) continue;

                for (self.meta.routes) |*route| {
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

            return count;
        }

        /// Result of proxy chain execution
        const ProxyResult = struct {
            aborted: bool = false,
            state_ptr: ?*const anyopaque = null,
        };

        /// Execute proxy chain: cascading Proxy() handlers + optional local proxy
        /// Returns ProxyResult with abort status and any state set by proxy
        fn executeProxyChain(
            self: *Self,
            path: []const u8,
            local_proxy: ?App.Meta.ProxyHandler,
            local_proxy_name: []const u8,
            req: zx.Request,
            res: zx.Response,
            arena: std.mem.Allocator,
        ) !ProxyResult {
            _ = local_proxy_name;
            var proxy_ctx = zx.ProxyContext.init(req, res, arena, arena);

            // Execute cascading Proxy() handlers (root to current path)
            var proxies: [16]App.Meta.ProxyHandler = undefined;
            const count = self.collectCascadingProxies(path, &proxies, arena);
            for (proxies[0..count]) |proxy_fn| {
                ProxyStatus.markExecuted();
                try proxy_fn(&proxy_ctx);
                if (proxy_ctx.isAborted()) {
                    ProxyStatus.markAborted();
                    return .{ .aborted = true, .state_ptr = proxy_ctx._state_ptr };
                }
            }

            // Execute local proxy (does NOT cascade)
            if (local_proxy) |proxy_fn| {
                ProxyStatus.markExecuted();
                try proxy_fn(&proxy_ctx);
                if (proxy_ctx.isAborted()) {
                    ProxyStatus.markAborted();
                    return .{ .aborted = true, .state_ptr = proxy_ctx._state_ptr };
                }
            }

            return .{ .aborted = false, .state_ptr = proxy_ctx._state_ptr };
        }

        /// Execute proxy handlers for page routes
        fn executePageProxy(self: *Self, route: *const App.Meta.Route, req: zx.Request, res: zx.Response, arena: std.mem.Allocator) !ProxyResult {
            return self.executeProxyChain(route.path, route.page_proxy, "PageProxy", req, res, arena);
        }

        /// Execute proxy handlers for API routes
        fn executeRouteProxy(self: *Self, route: *const App.Meta.Route, req: zx.Request, res: zx.Response, arena: std.mem.Allocator) !ProxyResult {
            return self.executeProxyChain(route.path, route.route_proxy, "RouteProxy", req, res, arena);
        }

        /// Execute proxy handlers for notfound routes (only cascading Proxy(), no local proxies)
        fn executeNotFoundProxy(self: *Self, _: *const App.Meta.Route, path: []const u8, req: zx.Request, res: zx.Response, arena: std.mem.Allocator) !ProxyResult {
            return self.executeProxyChain(path, null, "", req, res, arena);
        }

        pub fn api(self: *Self, req: *httpz.Request, res: *httpz.Response) !void {
            const allocator = self.allocator;
            const abstract_req = httpz_adapter.createRequest(req);
            const abstract_res = httpz_adapter.createResponse(res, req.arena);

            // Execute proxy handlers before API handling
            var proxy_state_ptr: ?*const anyopaque = null;
            if (req.route_data) |rd| {
                const route_data: *const App.Meta.Route = @ptrCast(@alignCast(rd));
                const proxy_result = try self.executeRouteProxy(route_data, abstract_req, abstract_res, req.arena);
                if (proxy_result.aborted) {
                    // Proxy handled the request, don't continue
                    return;
                }
                proxy_state_ptr = proxy_result.state_ptr;
            }

            if (req.route_data) |rd| {
                const route_data: *const App.Meta.Route = @ptrCast(@alignCast(rd));
                const handlers = route_data.route orelse return self.notFound(req, res);

                // Find the appropriate handler based on HTTP method
                const route_fn: ?App.Meta.RouteHandler = switch (req.method) {
                    .GET => handlers.get orelse handlers.handler,
                    .POST => handlers.post orelse handlers.handler,
                    .PUT => handlers.put orelse handlers.handler,
                    .DELETE => handlers.delete orelse handlers.handler,
                    .PATCH => handlers.patch orelse handlers.handler,
                    .HEAD => handlers.head orelse handlers.handler,
                    .OPTIONS => handlers.options orelse handlers.handler,
                    .OTHER => blk: {
                        // Look up custom method handler by method string
                        if (handlers.custom_methods) |custom_methods| {
                            for (custom_methods) |custom| {
                                if (std.mem.eql(u8, custom.method, req.method_string)) {
                                    break :blk custom.handler;
                                }
                            }
                        }
                        break :blk handlers.handler;
                    },
                    else => handlers.handler,
                };

                const handler = route_fn orelse return self.notFound(req, res);

                // Check if this route has a Socket handler and might want to upgrade
                if (handlers.socket) |socket_handler| {
                    // Create upgrade context for socket operations
                    var upgrade_ctx = httpz_adapter.SocketUpgradeContext{
                        .allocator = self.allocator,
                        .req = req,
                        .res = res,
                    };
                    const socket = httpz_adapter.createUpgradeSocket(&upgrade_ctx);
                    var routectx = zx.RouteContext.initWithAppPtrAndSocket(self.app_ctx, abstract_req, abstract_res, socket, allocator);
                    routectx._state_ptr = proxy_state_ptr;

                    handler(routectx) catch |err| {
                        return self.uncaughtError(req, res, err);
                    };

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
                    var routectx = zx.RouteContext.initWithAppPtr(self.app_ctx, abstract_req, abstract_res, allocator);
                    routectx._state_ptr = proxy_state_ptr;
                    handler(routectx) catch |err| {
                        return self.uncaughtError(req, res, err);
                    };
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

            // Execute proxy handlers before page handling
            var proxy_state_ptr: ?*const anyopaque = null;
            if (req.route_data) |rd| {
                const route: *const App.Meta.Route = @ptrCast(@alignCast(rd));
                const proxy_result = try self.executePageProxy(route, abstract_req, abstract_res, req.arena);
                if (proxy_result.aborted) {
                    // Proxy handled the request, don't continue
                    return;
                }
                proxy_state_ptr = proxy_result.state_ptr;
            }

            // Create page and layout contexts with type-erased app context and proxy state
            var pagectx = zx.PageContext.initWithAppPtr(self.app_ctx, abstract_req, abstract_res, allocator);
            pagectx._state_ptr = proxy_state_ptr;
            var layoutctx = zx.LayoutContext.initWithAppPtr(self.app_ctx, abstract_req, abstract_res, allocator);
            layoutctx._state_ptr = proxy_state_ptr;

            // log.debug("cli command: {s}", .{@tagName(meta.cli_command orelse .serve)});

            if (req.route_data) |rd| {
                const route: *const App.Meta.Route = @ptrCast(@alignCast(rd));

                // Check if this route has a page handler
                const page_fn = route.page orelse return self.notFound(req, res);

                // Handle route rendering with error handling
                blk: {
                    const normalized_route_path = route.path;

                    var page_component = page_fn(pagectx) catch |err| {
                        return self.uncaughtError(req, res, err);
                    };

                    // Find and apply parent layouts based on path hierarchy
                    // Collect all parent layouts from root to this route
                    var layouts_to_apply: [10]App.Meta.LayoutHandler = undefined;
                    var layouts_count: usize = 0;

                    // Build the path segments to traverse from root to current route
                    var path_segments = std.array_list.Managed([]const u8).init(pagectx.arena);
                    var path_iter = std.mem.splitScalar(u8, req.url.path, '/');
                    while (path_iter.next()) |segment| {
                        if (segment.len > 0) {
                            path_segments.append(segment) catch break :blk;
                        }
                    }

                    // First check root path "/"
                    // Only add root layout if current route is NOT the root route
                    // (root route's layout will be applied later as route.layout)
                    const is_root_route = std.mem.eql(u8, normalized_route_path, "/");
                    if (!is_root_route) {
                        for (self.meta.routes) |parent_route| {
                            const normalized_parent = parent_route.path;
                            if (std.mem.eql(u8, normalized_parent, "/")) {
                                if (parent_route.layout) |layout_fn| {
                                    if (layouts_count < layouts_to_apply.len) {
                                        layouts_to_apply[layouts_count] = layout_fn;
                                        layouts_count += 1;
                                    }
                                }
                                break;
                            }
                        }
                    }

                    // Traverse from root to current route, collecting layouts
                    // Only iterate if there are path segments beyond root
                    if (path_segments.items.len > 1) {
                        for (1..path_segments.items.len) |depth| {
                            // Build the path up to this depth
                            var path_buf: [256]u8 = undefined;
                            var path_stream = std.io.fixedBufferStream(&path_buf);
                            const path_writer = path_stream.writer();
                            _ = path_writer.write("/") catch break;

                            for (0..depth) |i| {
                                _ = path_writer.write(path_segments.items[i]) catch break;
                                if (i < depth - 1) {
                                    _ = path_writer.write("/") catch break;
                                }
                            }
                            const parent_path = path_buf[0 .. path_stream.getPos() catch break];

                            // Find route with matching path
                            // Skip if this parent path matches the current route (avoid double application)
                            if (std.mem.eql(u8, parent_path, normalized_route_path)) {
                                continue;
                            }
                            for (self.meta.routes) |parent_route| {
                                const normalized_parent = parent_route.path;
                                if (std.mem.eql(u8, normalized_parent, parent_path)) {
                                    if (parent_route.layout) |layout_fn| {
                                        if (layouts_count < layouts_to_apply.len) {
                                            layouts_to_apply[layouts_count] = layout_fn;
                                            layouts_count += 1;
                                        }
                                    }
                                    break;
                                }
                            }
                        }
                    }

                    // Apply this route's own layout first
                    if (route.layout) |layout_fn| {
                        page_component = layout_fn(layoutctx, page_component);
                    }

                    // Apply parent layouts in reverse order (leaf to root, most parent applied last)
                    var injector: ?ElementInjector = null;
                    if (is_dev_mode) {
                        injector = ElementInjector{ .allocator = pagectx.arena };
                    }

                    var i: usize = layouts_count;
                    while (i > 0) {
                        i -= 1;
                        page_component = layouts_to_apply[i](layoutctx, page_component);
                        // In dev mode, inject dev script into body element of root layout (last one applied, i == 0)
                        if (i == 0) {
                            if (injector != null) {
                                injectScripts(pagectx.arena, &page_component, .{ .dev = true });
                                injector = null; // Only inject once
                            }
                            if (comptime zx_options.client_enabled) {
                                injectScripts(pagectx.arena, &page_component, .{ .jsglue = true });
                            }
                        }
                    }

                    // Handle root route's own layout - inject dev script since it's the most parent
                    if (is_root_route) {
                        if (injector != null) {
                            injectScripts(pagectx.arena, &page_component, .{ .dev = true });
                        }
                        if (comptime zx_options.client_enabled) {
                            injectScripts(pagectx.arena, &page_component, .{ .jsglue = true });
                        }
                    }

                    // Check if streaming is enabled
                    const streaming_enabled = if (route.page_opts) |opts| opts.streaming else false;

                    if (streaming_enabled) {
                        // Streaming mode: render shell, collect async components, stream results
                        try self.renderStreaming(res, &page_component, pagectx.arena);
                    } else {
                        // Normal mode: render everything at once
                        const writer = &res.buffer.writer;
                        _ = writer.write("<!DOCTYPE html>\n") catch |err| {
                            std.debug.print("Error writing HTML: {}\n", .{err});
                            break :blk;
                        };
                        page_component.render(writer) catch |err| {
                            std.debug.print("Error rendering page: {}\n", .{err});
                            return self.uncaughtError(req, res, err);
                        };
                    }
                }

                res.content_type = .HTML;
                return;
            }
        }

        fn resolveStaticParams(self: *Self, allocator: Allocator, static_opts: zx.PageOptions.Static) ![]const []const zx.PageOptions.StaticParam {
            _ = self; // currently unused but keeps signature flexible
            var params = std.ArrayList([]const zx.PageOptions.StaticParam).empty;
            if (static_opts.params) |p| {
                try params.appendSlice(allocator, p);
            }

            if (static_opts.getParams) |getter| {
                const p = try getter(allocator);
                try params.appendSlice(allocator, p);
            }

            return try params.toOwnedSlice(allocator);
        }

        /// Render a page with streaming SSR support
        /// Sends the initial shell immediately, then streams async components as they complete
        fn renderStreaming(self: *Self, res: *httpz.Response, page_component: *Component, arena: std.mem.Allocator) !void {
            _ = self;

            var shell_writer = std.io.Writer.Allocating.init(arena);
            const async_components = page_component.stream(arena, &shell_writer.writer) catch |err| {
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
                res.chunk(Component.streaming_bootstrap_script) catch |err| {
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

                for (results) |*result| {
                    result.* = .{};
                }

                var remaining = std.atomic.Value(usize).init(async_components.len);

                const TaskContext = struct {
                    async_comp: Component.AsyncComponent,
                    result: *AsyncResult,
                    remaining: *std.atomic.Value(usize),

                    fn work(ctx: *@This()) void {
                        defer {
                            _ = ctx.remaining.fetchSub(1, .seq_cst);
                            std.heap.page_allocator.destroy(ctx);
                        }

                        const script = ctx.async_comp.renderScript(std.heap.page_allocator) catch |err| {
                            std.debug.print("Error rendering async component {d}: {}\n", .{ ctx.async_comp.id, err });
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
                        .remaining = &remaining,
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
                    for (results, 0..) |*result, i| {
                        if (streamed[i]) continue;

                        if (result.done.load(.seq_cst)) {
                            if (result.script.len > 0) {
                                res.chunk(result.script) catch |err| {
                                    std.debug.print("Error streaming async component: {}\n", .{err});
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
            const allocator = self.allocator;

            const assets_path = try std.fs.path.join(allocator, &.{ self.meta.rootdir, req.url.path });
            defer allocator.free(assets_path);

            const body = std.fs.cwd().readFileAlloc(allocator, assets_path, std.math.maxInt(usize)) catch |err| {
                switch (err) {
                    error.FileNotFound => return self.notFound(req, res),
                    else => return self.uncaughtError(req, res, err),
                }
            };

            res.content_type = httpz.ContentType.forFile(req.url.path);
            res.body = body;
        }

        pub fn public(self: *Self, req: *httpz.Request, res: *httpz.Response) !void {
            const allocator = self.allocator;

            const assets_path = try std.fs.path.join(allocator, &.{ self.meta.rootdir, "public", req.url.path });
            defer allocator.free(assets_path);

            const body = std.fs.cwd().readFileAlloc(allocator, assets_path, std.math.maxInt(usize)) catch |err| {
                switch (err) {
                    error.FileNotFound => return self.notFound(req, res),
                    else => return self.uncaughtError(req, res, err),
                }
            };

            res.body = body;
            res.content_type = httpz.ContentType.forFile(req.url.path);
        }

        const DevSocketContext = struct {
            const heartbeat_interval_ns = 30 * std.time.ns_per_s;
            fn handle(self: DevSocketContext, stream: std.net.Stream) void {
                _ = self;
                // Set retry interval to 100ms for fast reconnection when server restarts
                stream.writeAll("retry: 100\n\n") catch return;

                // Send periodic heartbeats to keep connection alive
                while (true) {
                    std.Thread.sleep(heartbeat_interval_ns);
                    stream.writeAll(":heartbeat\n\n") catch return;
                }
            }
        };

        pub fn devsocket(self: *Self, req: *httpz.Request, res: *httpz.Response) !void {
            _ = self;
            _ = req;

            res.header("X-Accel-Buffering", "no");

            // On windows there is a bug where the event stream is not working, so we just keep the connection alive
            if (builtin.os.tag == .windows) {
                res.content_type = .EVENTS;
                res.headers.add("Cache-Control", "no-cache");
                res.headers.add("Connection", "keep-alive");

                // res.writer().writeAll("retry: 100\n\n") catch return;
                // while (true) {
                //     std.Thread.sleep(DevSocketContext.heartbeat_interval_ns);
                //     res.writer().writeAll(":heartbeat\n\n") catch return;
                // }
            } else try res.startEventStream(DevSocketContext{}, DevSocketContext.handle);
        }

        /// Serve the dev script for hot reload
        pub fn devscript(_: *Self, _: *httpz.Request, res: *httpz.Response) !void {
            res.content_type = .JS;
            res.headers.add("Cache-Control", "no-cache");
            res.body = @embedFile("../../cli/transpile/template/devscript.js");
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
            allocator: std.mem.Allocator,
            upgrade_data: ?[]const u8,
            /// Subscriber data for pub/sub (stored directly on connection)
            subscriber: pubsub.SubscriberData,

            pub fn init(conn: *httpz.websocket.Conn, ctx: WebsocketContext) !WebsocketHandler {
                return .{
                    .conn = conn,
                    .socket_handler = ctx.socket_handler,
                    .socket_open_handler = ctx.socket_open_handler,
                    .socket_close_handler = ctx.socket_close_handler,
                    .allocator = ctx.allocator,
                    .upgrade_data = ctx.upgrade_data,
                    .subscriber = pubsub.SubscriberData.init(conn, ctx.allocator),
                };
            }

            /// Called after the WebSocket connection is established
            pub fn afterInit(self: *WebsocketHandler) !void {
                if (self.socket_open_handler) |handler| {
                    const socket = self.createSocket();
                    handler(socket, self.upgrade_data, self.allocator, self.allocator) catch |err| {
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
                    handler(socket, data, msg_type, self.upgrade_data, self.allocator, self.allocator) catch |err| {
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
                    handler(socket, self.upgrade_data, self.allocator);
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

const Allocator = std.mem.Allocator;
const Component = zx.Component;
const Printer = zx.Printer;
const App = zx.Server(void);
const Request = @import("../core/Request.zig");
const Response = @import("../core/Response.zig");
