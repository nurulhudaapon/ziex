const httpz = @import("httpz");
const app_opts = @import("app_opts");
const std = @import("std");
const builtin = @import("builtin");

const zx = @import("../../root.zig");
const tree = @import("../core/tree.zig");
const core_handler = @import("../core/Handler.zig");
const pubsub = @import("pubsub.zig");
const rndr = @import("render.zig");
const ctxs = @import("../core/contexts.zig");
const Server = @import("./Server.zig");
const AppConfig = @import("../core/AppConfig.zig");
const Request = @import("../core/Request.zig");
const Response = @import("../core/Response.zig");
const Constant = @import("../../constant.zig");
const PageCache = @import("PageCache.zig");

const Allocator = std.mem.Allocator;
const Component = zx.Component;
const ServerApp = Server.ServerApp;
const httpz_backend = zx.Http.Httpz;
const log = std.log.scoped(.app);

/// httpz backend handler.
/// Converts httpz types to abstract Request/Response, then delegates to core Handler.
/// Handles httpz-specific concerns: caching, dev logging, streaming, static files, WebSockets.
pub fn Handler(comptime AppCtxType: type) type {
    const cli_command = Server.cli_cmd;
    const is_dev = cli_command == .dev;
    const is_export = cli_command == .@"export";
    const feat_cache = app_opts.feat_cache_server;

    return struct {
        const Self = @This();

        meta: *ServerApp,
        config: AppConfig,
        page_cache: if (feat_cache) PageCache else void,
        allocator: std.mem.Allocator,
        app_ctx: *AppCtxType,
        io: std.Io,

        pub fn init(io: std.Io, allocator: std.mem.Allocator, meta: *ServerApp, config: AppConfig, app_ctx: *AppCtxType) !Self {
            const cache_config = config.cache;

            return Self{
                .meta = meta,
                .config = config,
                .allocator = allocator,
                .page_cache = if (feat_cache) try PageCache.initCachez(io, allocator, cache_config) else {},
                .app_ctx = app_ctx,
                .io = io,
            };
        }

        pub fn deinit(self: *Self) void {
            if (feat_cache) self.page_cache.deinit();
        }

        pub fn dispatch(self: *Self, action: httpz.Action(*Self), req: *httpz.Request, res: *httpz.Response) !void {
            var start_time = if (comptime is_dev) std.Io.Timestamp.now(self.io, .awake) else std.Io.Timestamp.zero;

            // Reset proxy status for this request (dev mode tracking)
            if (comptime is_dev) ProxyStatus.reset();

            // Try cache first, execute action on miss
            // Note: Middlewares are handled by httpz before this dispatch is called
            var hctx = httpz_backend.HttpzCtx{ .req = req, .res = res };
            const abstract_req = httpz_backend.createRequest(&hctx);
            const abstract_res = httpz_backend.createResponse(&hctx, req.arena);

            const cache_status = if (feat_cache) self.page_cache.tryServe(abstract_req, abstract_res) else PageCache.Status.disabled;
            if (cache_status != .hit) {
                try action(self, req, res);
                if (cache_status == .miss) {
                    const buffered = res.buffer.writer.buffered();
                    const body = if (buffered.len > 0) buffered else res.body;
                    self.page_cache.store(abstract_req, abstract_res, .{
                        .status = res.status,
                        .body = body,
                        .content_type = httpzContentTypeMime(res.content_type),
                    });
                }
            }

            // Dev mode logging (skip noisy paths)
            if ((comptime is_dev) and !isNoisyPath(req.url.path)) {
                const end_time = std.Io.Timestamp.now(self.io, .awake);
                const elapsed_ns = start_time.durationTo(end_time).nanoseconds;
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

                const msg = std.fmt.allocPrint(req.arena, "{s}{s}{s}{s} {s}{s}{s} {s}{d}{s} {s}{d:.3}ms{s}\x1b[K", .{
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

        pub fn notFound(_: *Self, req: *httpz.Request, res: *httpz.Response) !void {
            const path = req.url.path;

            var hctx = httpz_backend.HttpzCtx{ .req = req, .res = res };
            const abstract_req = httpz_backend.createRequest(&hctx);
            const abstract_res = httpz_backend.createResponse(&hctx, req.arena);

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
            const matched_route: ?*const ServerApp.Route = if (req.route_data) |rd|
                @ptrCast(@alignCast(rd))
            else
                null;

            if (core_handler.renderNotFound(path, abstract_req, abstract_res, req.arena, matched_route)) |cmp| {
                var component = cmp;

                // Dev mode: inject dev script
                if (cli_command == .dev) {
                    injectDevScript(req.arena, &component);
                }

                // Write to response
                res.clearWriter();
                const writer = res.writer();
                writer.writeAll("<!DOCTYPE html>\n") catch {
                    res.body = "404 Not Found";
                    return;
                };
                component.render(writer, .{ .base_path = app_opts.app_base_path }) catch {
                    res.body = "404 Not Found";
                };
            } else {
                res.body = "404 Not Found";
            }
        }

        pub fn uncaughtError(_: *Self, req: *httpz.Request, res: *httpz.Response, err: anyerror) void {
            const path = req.url.path;

            res.status = 500;
            res.content_type = .HTML;

            var hctx = httpz_backend.HttpzCtx{ .req = req, .res = res };
            const abstract_req = httpz_backend.createRequest(&hctx);
            const abstract_res = httpz_backend.createResponse(&hctx, req.arena);

            // Delegate to core handler for error rendering
            if (core_handler.renderError(path, abstract_req, abstract_res, req.arena, err)) |cmp| {
                var component = cmp;

                // Dev mode: inject dev script
                if (cli_command == .dev) {
                    injectDevScript(req.arena, &component);
                }

                // Write to response
                res.clearWriter();
                const writer = res.writer();
                writer.writeAll("<!DOCTYPE html>\n") catch {
                    res.body = "500 Internal Server Error";
                    return;
                };
                component.render(writer, .{ .base_path = app_opts.app_base_path }) catch {
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
            var hctx = httpz_backend.HttpzCtx{ .req = req, .res = res };
            const abstract_req = httpz_backend.createRequest(&hctx);
            const abstract_res = httpz_backend.createResponse(&hctx, req.arena);

            // Get route data
            const route_data: *const ServerApp.Route = if (req.route_data) |rd|
                @ptrCast(@alignCast(rd))
            else
                return self.notFound(req, res);

            // Static export
            if (comptime is_export) {
                if (req.header("x-zx-static-data")) |_| {
                    if (route_data.route_opts) |page_opts| {
                        if (page_opts.static) |static_opts| {
                            const params = try self.resolveStaticParams(req.arena, static_opts);
                            try std.zon.stringify.serialize(params, .{ .whitespace = true }, res.writer());
                        }
                    }

                    return;
                }
            }

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
                var upgrade_ctx = httpz_backend.UpgradeBackend{
                    .allocator = allocator,
                    .req = req,
                    .res = res,
                };
                const socket = upgrade_ctx.socket();

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

            if (comptime is_export) {
                if (req.header("x-zx-export-notfound")) |_| {
                    return self.notFound(req, res);
                }

                // Handle static params request for dynamic routes
                if (req.header("x-zx-static-data")) |_| {
                    if (req.route_data) |rd| {
                        const route: *const ServerApp.Route = @ptrCast(@alignCast(rd));
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

            var hctx = httpz_backend.HttpzCtx{ .req = req, .res = res };
            const abstract_req = httpz_backend.createRequest(&hctx);
            const abstract_res = httpz_backend.createResponse(&hctx, req.arena);

            // Get route data
            const route: *const ServerApp.Route = if (req.route_data) |rd|
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
                app_opts.app_base_path,
            );

            switch (result) {
                .component => |cmp| {
                    var page_component = cmp;

                    // Dev mode: inject dev script
                    if (comptime is_dev) {
                        injectDevScript(req.arena, &page_component);
                    }

                    // Handle devtool request
                    const is_devtool = std.mem.eql(u8, req.url.path, "/.well-known/_zx/devtool");
                    if ((comptime is_dev) and is_devtool) {
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
                        page_component.render(writer, .{ .base_path = app_opts.app_base_path }) catch |err| {
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
                        app_opts.app_base_path,
                    );
                    switch (re_result) {
                        .component => |cmp| {
                            var page_component = cmp;
                            if (comptime is_dev) injectDevScript(req.arena, &page_component);
                            const writer = &res.buffer.writer;
                            _ = writer.write("<!DOCTYPE html>\n") catch return;
                            page_component.render(writer, .{ .base_path = app_opts.app_base_path }) catch |err| return self.uncaughtError(req, res, err);
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

        fn resolveStaticParams(self: *Self, allocator_arg: Allocator, static_fn: zx.StaticFn) ![]const []const zx.StaticParam {
            _ = self;
            var ctx = zx.StaticContext.init(allocator_arg);
            try static_fn(&ctx);
            return try ctx.params.entries.toOwnedSlice(allocator_arg);
        }

        /// Render a page with streaming SSR support
        /// Sends the initial shell immediately, then streams async components as they complete
        fn renderStreaming(self: *Self, res: *httpz.Response, page_component: *Component, arena: std.mem.Allocator) !void {
            var shell_writer = std.Io.Writer.Allocating.init(arena);
            const async_components = rndr.stream(page_component.*, arena, &shell_writer.writer, .{ .base_path = app_opts.app_base_path }) catch |err| {
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
                        _ = try std.Io.sleep(self.io, std.Io.Duration.fromMilliseconds(5), .awake);
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
            const staticdir = self.config.staticdir orelse Constant.default_staticdir;
            const assets_path = try std.fs.path.join(res.arena, &.{ staticdir, req.url.path });

            const body = std.Io.Dir.cwd().readFileAlloc(self.io, assets_path, res.arena, .unlimited) catch |err| {
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
            socket_handler: ?ServerApp.SocketHandler = null,
            socket_open_handler: ?ServerApp.SocketOpenHandler = null,
            socket_close_handler: ?ServerApp.SocketCloseHandler = null,
            allocator: std.mem.Allocator = std.heap.page_allocator,
            /// Copied user data bytes passed during upgrade
            upgrade_data: ?[]const u8 = null,
        };

        pub const WebsocketHandler = struct {
            conn: *httpz.websocket.Conn,
            socket_handler: ?ServerApp.SocketHandler,
            socket_open_handler: ?ServerApp.SocketOpenHandler,
            socket_close_handler: ?ServerApp.SocketCloseHandler,
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

            /// Create a Socket interface for the current connection, backed by
            /// this handler via the unified `Http` vtable (only `ws*` slots).
            fn createSocket(self: *WebsocketHandler) zx.Socket {
                return .{ ._internal = .{
                    .http = .{ .userdata = @ptrCast(self), .vtable = &socket_vtable },
                    .attached = true,
                } };
            }

            const socket_vtable = blk: {
                var vt = zx.Http.failing_vtable;
                vt.wsWrite = &socketWrite;
                vt.wsClose = &socketClose;
                vt.wsSubscribe = &socketSubscribe;
                vt.wsUnsubscribe = &socketUnsubscribe;
                vt.wsPublish = &socketPublish;
                vt.wsIsSubscribed = &socketIsSubscribed;
                vt.wsSetPublishToSelf = &socketSetPublishToSelf;
                break :blk vt;
            };

            fn handlerOf(userdata: ?*anyopaque) *WebsocketHandler {
                return @ptrCast(@alignCast(userdata.?));
            }

            fn socketWrite(userdata: ?*anyopaque, data: []const u8) anyerror!void {
                try handlerOf(userdata).conn.write(data);
            }

            fn socketClose(userdata: ?*anyopaque) void {
                handlerOf(userdata).conn.close(.{ .code = 1000, .reason = "closed" }) catch {};
            }

            // Pub/Sub vtable implementations - use subscriber data stored on connection
            fn socketSubscribe(userdata: ?*anyopaque, topic: []const u8) void {
                handlerOf(userdata).subscriber.subscribe(topic);
            }

            fn socketUnsubscribe(userdata: ?*anyopaque, topic: []const u8) void {
                handlerOf(userdata).subscriber.unsubscribe(topic);
            }

            fn socketPublish(userdata: ?*anyopaque, topic: []const u8, message: []const u8) usize {
                const handler = handlerOf(userdata);
                return pubsub.getPubSub().publish(&handler.subscriber, topic, message);
            }

            fn socketIsSubscribed(userdata: ?*anyopaque, topic: []const u8) bool {
                return handlerOf(userdata).subscriber.isSubscribed(topic);
            }

            fn socketSetPublishToSelf(userdata: ?*anyopaque, value: bool) void {
                handlerOf(userdata).subscriber.publish_to_self = value;
            }
        };
    };
}

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

        const effective_cache = PageCache.effectiveStatus(cache_status, http_status);

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

fn httpzContentTypeMime(ct: ?httpz.ContentType) ?[]const u8 {
    return if (ct) |c| switch (c) {
        .BINARY => "application/octet-stream",
        .CSS => "text/css",
        .CSV => "text/csv",
        .EOT => "application/vnd.ms-fontobject",
        .EVENTS => "text/event-stream",
        .GIF => "image/gif",
        .GZ => "application/gzip",
        .HTML => "text/html",
        .ICO => "image/vnd.microsoft.icon",
        .JPG => "image/jpeg",
        .JS => "text/javascript",
        .JSON => "application/json",
        .OTF => "font/otf",
        .PDF => "application/pdf",
        .PNG => "image/png",
        .SVG => "image/svg+xml",
        .TAR => "application/x-tar",
        .TEXT => "text/plain",
        .TTF => "font/ttf",
        .WASM => "application/wasm",
        .WEBP => "image/webp",
        .WOFF => "font/woff",
        .WOFF2 => "font/woff2",
        .XML => "text/xml",
        .UNKNOWN => null,
    } else null;
}
