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

/// PageCache handles caching of rendered HTML pages with ETag support
const PageCache = struct {
    pub const Status = enum {
        hit, // Served from cache
        miss, // Not in cache, freshly rendered
        skip, // Not cacheable (POST, internal paths, etc.)
        disabled, // Cache is disabled

        pub fn indicator(self: Status, http_status: u16) []const u8 {
            if (self == .disabled) return "";
            const status = if (isCacheableHttpStatus(http_status)) self else Status.skip;

            return switch (status) {
                .hit => "\x1b[1;32m[>]\x1b[0m ", // green [>]
                .miss => "\x1b[1;33m[o]\x1b[0m ", // yellow [o]
                .skip => "\x1b[2m[-]\x1b[0m ", // dim [-]
                .disabled => "",
            };
        }
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
                    self.addCacheHeaders(res, entry.value.etag);
                    return .hit;
                }
            }
        }

        // Try to serve full cached response
        if (self.cache.get(req.url.path)) |entry| {
            defer entry.release();
            res.content_type = entry.value.content_type;
            res.body = entry.value.body;
            self.addCacheHeaders(res, entry.value.etag);
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
        self.addCacheHeaders(res, etag);
        res.headers.add("X-Cache", "MISS");
    }

    fn addCacheHeaders(self: *PageCache, res: *httpz.Response, etag: []const u8) void {
        res.headers.add("ETag", etag);
        res.headers.add("Cache-Control", std.fmt.allocPrint(self.allocator, "public, max-age={d}", .{self.config.default_ttl}) catch "public, max-age=300");
        res.headers.add("X-Cache", "HIT");
    }

    fn isCacheable(req: *httpz.Request) bool {
        if (getTtl(req) == null) return false;
        if (req.method != .GET) return false;
        if (std.mem.startsWith(u8, req.url.path, "/_zx/")) return false;
        if (std.mem.startsWith(u8, req.url.path, "/assets/_zx/")) return false;
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
                return options.caching.getSeconds();
            }
        }
        return null;
    }
};

pub const Handler = struct {
    meta: *App.Meta,
    page_cache: PageCache,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, meta: *App.Meta, cache_config: CacheConfig) !Handler {
        return .{
            .meta = meta,
            .allocator = allocator,
            .page_cache = try PageCache.init(allocator, cache_config),
        };
    }

    pub fn deinit(self: *Handler) void {
        self.page_cache.deinit();
    }

    pub fn dispatch(self: *Handler, action: httpz.Action(*Handler), req: *httpz.Request, res: *httpz.Response) !void {
        const is_dev = self.meta.cli_command == .dev;
        var timer = if (is_dev) try std.time.Timer.start() else null;

        // Try cache first, execute action on miss
        const cache_status = self.page_cache.tryServe(req, res);
        if (cache_status != .hit) {
            try action(self, req, res);
            if (cache_status == .miss) self.page_cache.store(req, res);
        }

        // Dev mode logging
        if (is_dev) {
            const elapsed_ns = timer.?.lap();
            const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(std.time.ns_per_ms));
            const c = struct {
                const reset = "\x1b[0m";
                const method = "\x1b[1;34m"; // bold blue
                const path = "\x1b[1;36m"; // bold cyan
                fn time(ms: f64) []const u8 {
                    return if (ms < 10) "\x1b[1;32m" else if (ms < 100) "\x1b[1;33m" else "\x1b[1;31m";
                }
                fn status(code: u16) []const u8 {
                    return if (code < 300) "\x1b[1;32m" else if (code < 400) "\x1b[1;33m" else "\x1b[1;31m";
                }
            };

            std.log.info("{s}{s}{s}{s} {s}{s}{s} {s}{d}{s} {s}{d:.3}ms{s}\x1b[K", .{
                cache_status.indicator(res.status),
                c.method,
                @tagName(req.method),
                c.reset,
                c.path,
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

    pub fn notFound(self: *Handler, req: *httpz.Request, res: *httpz.Response) !void {
        std.log.info("404 {} {s}", .{ req.method, req.url.path });
        const path = req.url.path;

        res.status = 404;
        res.content_type = .HTML;

        const notfoundctx = zx.NotFoundContext.init(req, res, self.allocator);

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
        self.renderErrorPage(req, res, notfound_cmp, .{
            .fallback_message = "Internal Server Error, notfound page rendering failed",
        });
    }

    pub fn uncaughtError(self: *Handler, req: *httpz.Request, res: *httpz.Response, err: anyerror) void {
        std.log.info("500 {} {s} {}", .{ req.method, req.url.path, err });
        const path = req.url.path;

        res.status = 500;
        res.content_type = .HTML;

        const errorctx = zx.ErrorContext.init(req, res, self.allocator, err);

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
        self.renderErrorPage(req, res, error_cmp, .{
            .fallback_message = "Internal Server Error, error page rendering failed",
        });
    }

    const RenderErrorPageOptions = struct {
        fallback_message: []const u8 = "Internal Server Error",
    };

    /// Shared method to render error/notfound pages wrapped in parent layouts
    fn renderErrorPage(
        self: *Handler,
        req: *httpz.Request,
        res: *httpz.Response,
        page_component: Component,
        opts: RenderErrorPageOptions,
    ) void {
        const path = req.url.path;
        const layoutctx = zx.LayoutContext.init(req, res, self.allocator);
        const is_dev_mode = self.meta.cli_command == .dev;

        var component = page_component;

        // Collect all parent layouts from root to deepest
        var layouts_to_apply: [10]*const fn (ctx: zx.LayoutContext, component: Component) Component = undefined;
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
            if (injector) |*inj| {
                if (j == 0) {
                    _ = inj.injectScriptIntoBody(&component, "/assets/_zx/devscript.js");
                    injector = null;
                }
            }
        }

        // If no layouts were applied but we're in dev mode, still try to inject
        if (layouts_count == 0 and is_dev_mode) {
            const inj = ElementInjector{ .allocator = req.arena };
            _ = inj.injectScriptIntoBody(&component, "/assets/_zx/devscript.js");
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
        self: *Handler,
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

    pub fn page(self: *Handler, req: *httpz.Request, res: *httpz.Response) !void {
        const allocator = self.allocator;

        const pagectx = zx.PageContext.init(req, res, allocator);
        const layoutctx = zx.LayoutContext.init(req, res, allocator);

        const is_dev_mode = self.meta.cli_command == .dev;
        // log.debug("cli command: {s}", .{@tagName(meta.cli_command orelse .serve)});

        if (req.route_data) |rd| {
            const route: *const App.Meta.Route = @ptrCast(@alignCast(rd));

            // Handle route rendering with error handling
            blk: {
                const normalized_route_path = route.path;

                var page_component = route.page(pagectx);

                // Find and apply parent layouts based on path hierarchy
                // Collect all parent layouts from root to this route
                var layouts_to_apply: [10]*const fn (ctx: zx.LayoutContext, component: Component) Component = undefined;
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
                    if (injector) |*inj| {
                        if (i == 0) {
                            _ = inj.injectScriptIntoBody(&page_component, "/assets/_zx/devscript.js");
                            injector = null; // Only inject once
                        }
                    }
                }

                // Handle root route's own layout - inject dev script since it's the most parent
                if (is_root_route) {
                    if (injector) |*inj| {
                        _ = inj.injectScriptIntoBody(&page_component, "/assets/_zx/devscript.js");
                    }
                }

                const writer = &layoutctx.response.buffer.writer;
                _ = writer.write("<!DOCTYPE html>\n") catch |err| {
                    std.debug.print("Error writing HTML: {}\n", .{err});
                    break :blk;
                };
                page_component.render(writer) catch |err| {
                    std.debug.print("Error rendering page: {}\n", .{err});
                    break :blk;
                };
            }

            res.content_type = .HTML;
            return;
        }
    }

    pub fn assets(self: *Handler, req: *httpz.Request, res: *httpz.Response) !void {
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

    pub fn public(self: *Handler, req: *httpz.Request, res: *httpz.Response) !void {
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

    pub fn devsocket(self: *Handler, req: *httpz.Request, res: *httpz.Response) !void {
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
};

const std = @import("std");
const builtin = @import("builtin");
const cachez = @import("cachez");
const zx = @import("../root.zig");

const Allocator = std.mem.Allocator;
const Component = zx.Component;
const Printer = zx.Printer;
const App = zx.App;
