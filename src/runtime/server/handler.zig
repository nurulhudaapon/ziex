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

            const is_devtool_req = (comptime is_dev) and req.header("x-zx-devtool") != null;
            const cache_status = if (feat_cache and !is_devtool_req) self.page_cache.tryServe(abstract_req, abstract_res) else PageCache.Status.disabled;
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

        pub fn notFound(self: *Self, req: *httpz.Request, res: *httpz.Response) !void {
            var hctx = httpz_backend.HttpzCtx{ .req = req, .res = res };
            const abstract_req = httpz_backend.createRequest(&hctx);
            const abstract_res = httpz_backend.createResponse(&hctx, req.arena);
            const http = hctx.http();
            const path = req.url.path;

            const matched_route: ?*const ServerApp.Route = if (req.route_data) |rd|
                @ptrCast(@alignCast(rd))
            else
                zx.Router.findRoute(path, .{ .match = .exact });

            const proxy_result = core_handler.executeNotFoundProxy(path, abstract_req, abstract_res, req.arena, self.io);
            if (proxy_result.aborted) {
                ProxyStatus.markAborted();
                return;
            }
            if (proxy_result.state_ptr != null) ProxyStatus.markExecuted();

            const component = core_handler.prepareNotFound(http, path, abstract_req, abstract_res, req.arena, self.io, matched_route);
            try self.emitHtmlOrPlain(req, res, component);
        }

        pub fn uncaughtError(self: *Self, req: *httpz.Request, res: *httpz.Response, err: anyerror) void {
            var hctx = httpz_backend.HttpzCtx{ .req = req, .res = res };
            const abstract_req = httpz_backend.createRequest(&hctx);
            const abstract_res = httpz_backend.createResponse(&hctx, req.arena);
            const http = hctx.http();

            const component = core_handler.prepareError(http, req.url.path, abstract_req, abstract_res, req.arena, self.io, err);
            self.emitHtmlOrPlain(req, res, component) catch {
                res.body = "500 Internal Server Error";
            };
        }

        fn injectDevScript(arena: Allocator, component: *Component) void {
            const inj = ElementInjector{ .allocator = arena };
            _ = inj.injectScriptIntoBody(component, "/.well-known/_zx/devscript.js");
        }

        fn markProxyStatus(proxy: zx.Router.ProxyResult) void {
            if (proxy.aborted) {
                ProxyStatus.markAborted();
            } else if (proxy.state_ptr != null) {
                ProxyStatus.markExecuted();
            }
        }

        fn emitHtmlOrPlain(self: *Self, req: *httpz.Request, res: *httpz.Response, component: ?Component) !void {
            _ = self;
            if (component) |cmp| {
                var page_component = cmp;
                if (comptime is_dev) injectDevScript(req.arena, &page_component);

                res.clearWriter();
                const writer = res.writer();
                core_handler.renderHtmlDocument(writer, &page_component, app_opts.app_base_path) catch {
                    if (res.body.len == 0) {
                        res.body = if (res.status == 404) "404 Not Found" else "500 Internal Server Error";
                    }
                };
                res.content_type = .HTML;
            } else {
                res.content_type = .HTML;
                // prepare* already set res.body via Http.resSetBody
            }
        }

        /// Shared page/API entry used by both httpz registrations.
        pub fn api(self: *Self, req: *httpz.Request, res: *httpz.Response) !void {
            return self.dispatchRequest(req, res);
        }

        pub fn page(self: *Self, req: *httpz.Request, res: *httpz.Response) !void {
            return self.dispatchRequest(req, res);
        }

        fn dispatchRequest(self: *Self, req: *httpz.Request, res: *httpz.Response) !void {
            const allocator = self.allocator;

            if (comptime is_dev) {
                if (try self.devtool(req, res)) return;
            }

            // Export-only early outs
            if (comptime is_export) {
                if (req.header("x-zx-export-notfound")) |_| {
                    return self.notFound(req, res);
                }
                if (req.route_data) |rd| {
                    const route: *const ServerApp.Route = @ptrCast(@alignCast(rd));
                    if (req.header("x-zx-static-data")) |_| {
                        const static_opts = blk: {
                            if (route.page_opts) |page_opts| {
                                if (page_opts.static) |s| break :blk s;
                            }
                            if (route.route_opts) |route_opts| {
                                if (route_opts.static) |s| break :blk s;
                            }
                            break :blk null;
                        };
                        if (static_opts) |static_fn| {
                            const params = try self.resolveStaticParams(req.arena, static_fn);
                            try std.zon.stringify.serialize(params, .{ .whitespace = true }, res.writer());
                        }
                        return;
                    }

                    const is_dynamic = blk: {
                        if (route.page_opts) |page_opts| {
                            if (page_opts.dynamic) break :blk true;
                        }
                        if (route.route_opts) |route_opts| {
                            if (route_opts.dynamic) break :blk true;
                        }
                        break :blk false;
                    };
                    if (is_dynamic) {
                        res.header("x-zx-dynamic", "true");
                        try std.zon.stringify.serialize(.{ .dynamic = true }, .{ .whitespace = true }, res.writer());
                        return;
                    }
                }
            }

            var hctx = httpz_backend.HttpzCtx{ .req = req, .res = res };
            const abstract_req = httpz_backend.createRequest(&hctx);
            const abstract_res = httpz_backend.createResponse(&hctx, req.arena);
            const http = hctx.http();

            const route: ?*const ServerApp.Route = if (req.route_data) |rd|
                @ptrCast(@alignCast(rd))
            else
                null;

            var upgrade_ctx = httpz_backend.UpgradeBackend{
                .allocator = allocator,
                .req = req,
                .res = res,
            };
            var use_socket = false;
            const socket: zx.Socket = blk: {
                if (route) |r| {
                    if (r.route) |handlers| {
                        if (handlers.socket != null) {
                            use_socket = true;
                            break :blk upgrade_ctx.socket();
                        }
                    }
                }
                break :blk .{};
            };

            const result = try zx.Router.handle(.{ .is_dev = is_dev }, .{
                .http = http,
                .request = abstract_req,
                .response = abstract_res,
                .pathname = req.url.path,
                .method = abstract_req.method,
                .allocator = allocator,
                .arena = req.arena,
                .io = self.io,
                .base_path = app_opts.app_base_path,
                .app_ctx = @ptrCast(self.app_ctx),
                .socket = socket,
            });
            markProxyStatus(result.proxy);

            switch (result.outcome) {
                .response_ready => {},
                .component => |c| {
                    var page_component = c.component;

                    if (comptime is_dev) {
                        if (req.header("x-zx-devtool")) |mode| {
                            if (std.mem.eql(u8, mode, "components")) {
                                const include_native = !std.mem.eql(u8, req.header("x-zx-devtool-include-native") orelse "1", "0");
                                res.content_type = .JSON;
                                try zx.util.devtool.formatWithOptions(page_component, res.writer(), .{ .only_components = !include_native });
                                return;
                            }
                        }
                        injectDevScript(req.arena, &page_component);
                    }

                    if (c.streaming) {
                        try self.renderStreaming(res, &page_component, req.arena);
                    } else {
                        const writer = &res.buffer.writer;
                        core_handler.renderHtmlDocument(writer, &page_component, app_opts.app_base_path) catch |err| switch (err) {
                            error.NotFound => return self.notFound(req, res),
                            else => {
                                log.err("rendering page: {}", .{err});
                                return self.uncaughtError(req, res, err);
                            },
                        };
                    }
                    res.content_type = .HTML;
                },
                .ws_upgraded => {
                    if (use_socket and upgrade_ctx.upgraded) {
                        if (route) |r| {
                            if (r.route) |handlers| {
                                const ws_ctx = WebsocketContext{
                                    .socket_handler = handlers.socket,
                                    .socket_open_handler = handlers.socket_open,
                                    .socket_close_handler = handlers.socket_close,
                                    .allocator = allocator,
                                    .io = self.io,
                                    .upgrade_data = upgrade_ctx.upgrade_data,
                                };
                                if (try httpz.upgradeWebsocket(WebsocketHandler, req, res, ws_ctx) == false) {
                                    res.status = 400;
                                    res.body = "Invalid WebSocket handshake";
                                }
                            }
                        }
                    }
                },
                .not_found => |nf| {
                    try self.emitHtmlOrPlain(req, res, nf.component);
                },
            }
        }

        /// Returns true when the request was fully handled.
        fn devtool(self: *Self, req: *httpz.Request, res: *httpz.Response) !bool {
            const mode = req.header("x-zx-devtool") orelse return false;
            res.header("Access-Control-Allow-Origin", "*");
            res.header("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
            res.header("Access-Control-Allow-Headers", "Content-Type, x-zx-devtool, x-zx-devtool-include-native");
            res.header("Access-Control-Allow-Private-Network", "true");

            if (req.method == .OPTIONS) {
                res.status = 200;
                return true;
            }

            if (std.mem.eql(u8, mode, "meta")) {
                const meta_data = try zx.server.SerilizableAppMeta.init(req.arena, self.meta, self.config.server);
                res.content_type = .JSON;
                try meta_data.serializeRoutes(res.writer());
                return true;
            }
            // "components" continues through normal page render.
            return false;
        }

        fn resolveStaticParams(self: *Self, allocator_arg: Allocator, static_fn: zx.StaticFn) ![]const []const zx.StaticParam {
            var ctx = zx.StaticContext.init(allocator_arg, self.io);
            try static_fn(&ctx);
            return try ctx.params.entries.toOwnedSlice(allocator_arg);
        }

        /// Render a page with streaming SSR support
        /// Sends the initial shell immediately, then streams async components as they complete
        fn renderStreaming(self: *Self, res: *httpz.Response, page_component: *Component, arena: std.mem.Allocator) !void {
            var shell_writer = std.Io.Writer.Allocating.init(arena);
            const async_components = rndr.stream(page_component.*, arena, &shell_writer.writer, .{ .base_path = app_opts.app_base_path }) catch |err| {
                log.err("streaming page: {}", .{err});
                return err;
            };

            res.chunk("<!DOCTYPE html>\n") catch |err| {
                log.err("sending DOCTYPE: {}", .{err});
                return err;
            };
            res.chunk(shell_writer.written()) catch |err| {
                log.err("sending shell: {}", .{err});
                return err;
            };

            if (async_components.len > 0) {
                res.chunk(rndr.streaming_bootstrap_script) catch |err| {
                    log.err("sending bootstrap script: {}", .{err});
                    return err;
                };
                const AsyncResult = struct {
                    script: []const u8 = &.{},
                    done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
                };

                const results = std.heap.page_allocator.alloc(AsyncResult, async_components.len) catch |err| {
                    log.err("allocating results: {}", .{err});
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
                            log.err("rendering async component {d}: {}", .{ ctx.async_comp.id, work_err });
                            ctx.result.done.store(true, .seq_cst);
                            return;
                        };

                        ctx.result.script = script;
                        ctx.result.done.store(true, .seq_cst);
                    }
                };

                var threads = std.heap.page_allocator.alloc(?std.Thread, async_components.len) catch |err| {
                    log.err("allocating threads: {}", .{err});
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
                    log.err("allocating streamed flags: {}", .{err});
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
                                    log.err("streaming async component: {}", .{chunk_err});
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
            io: std.Io = .failing,
            /// Copied user data bytes passed during upgrade
            upgrade_data: ?[]const u8 = null,
        };

        pub const WebsocketHandler = struct {
            conn: *httpz.websocket.Conn,
            socket_handler: ?ServerApp.SocketHandler,
            socket_open_handler: ?ServerApp.SocketOpenHandler,
            socket_close_handler: ?ServerApp.SocketCloseHandler,
            ws_allocator: std.mem.Allocator,
            io: std.Io,
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
                    .io = ctx.io,
                    .upgrade_data = ctx.upgrade_data,
                    .subscriber = pubsub.SubscriberData.init(conn, ctx.allocator),
                };
            }

            /// Called after the WebSocket connection is established
            pub fn afterInit(self: *WebsocketHandler) !void {
                if (self.socket_open_handler) |handler| {
                    const socket = self.createSocket();
                    handler(socket, self.upgrade_data, self.ws_allocator, self.ws_allocator, self.io) catch |err| {
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
                    handler(socket, data, msg_type, self.upgrade_data, self.ws_allocator, self.ws_allocator, self.io) catch |err| {
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
                    handler(socket, self.upgrade_data, self.ws_allocator, self.io);
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
                log.err("allocating attributes: OOM", .{});
                return false;
            };
            attributes[0] = .{ .name = "src", .value = script_src };
            const script_element = Component{ .element = .{ .tag = .script, .attributes = attributes } };
            tree.appendChild(body_element, self.allocator, script_element) catch |err| {
                log.err("appending script to body: {}", .{err});
                self.allocator.free(attributes);
                return false;
            };
            return true;
        }
        return false;
    }

    pub fn injectZxInjections(self: ElementInjector, page: *Component, pathname: []const u8) void {
        core_handler.injectZxInjections(self.allocator, page, pathname);
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

// TODO: put this in docs
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
