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

pub const Handler = struct {
    meta: *App.Meta,
    allocator: std.mem.Allocator,

    pub fn dispatch(self: *Handler, action: httpz.Action(*Handler), req: *httpz.Request, res: *httpz.Response) !void {
        if (self.meta.cli_command != .dev)
            return try action(self, req, res);

        // Dev mode logging
        const is_zx_path = std.mem.startsWith(u8, req.url.path, "/_zx/") or std.mem.startsWith(u8, req.url.path, "/assets/_zx/");
        if (is_zx_path) return try action(self, req, res);

        var timer = try std.time.Timer.start();

        try action(self, req, res);

        const elapsed_ns = timer.lap();
        const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(std.time.ns_per_ms));
        const color_reset = "\x1b[0m";
        const color_method = "\x1b[1;34m"; // bold blue
        const color_path = "\x1b[1;36m"; // bold cyan
        const color_time = if (elapsed_ms < 10) "\x1b[1;32m" else if (elapsed_ms < 100) "\x1b[1;33m" else "\x1b[1;31m"; // green/yellow/red based on time
        const status_code = res.status;
        const color_status = if (status_code < 300) "\x1b[1;32m" else if (status_code < 400) "\x1b[1;33m" else "\x1b[1;31m"; // green/yellow/red based on status

        std.log.info("{s}{s}{s} {s}{s}{s} {s}{d}{s} {s}{d:.3}ms{s}\x1b[K", .{
            color_method, @tagName(req.method), color_reset,
            color_path,   req.url.path,         color_reset,
            color_status, status_code,          color_reset,
            color_time,   elapsed_ms,           color_reset,
        });
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

        res.content_type = httpz.ContentType.forFile(req.url.path);
        res.body = std.fs.cwd().readFileAlloc(allocator, assets_path, std.math.maxInt(usize)) catch {
            res.setStatus(.not_found);
            return;
        };
    }

    pub fn public(self: *Handler, req: *httpz.Request, res: *httpz.Response) !void {
        const allocator = self.allocator;

        const assets_path = try std.fs.path.join(allocator, &.{ self.meta.rootdir, "public", req.url.path });
        defer allocator.free(assets_path);

        res.content_type = httpz.ContentType.forFile(req.url.path);
        res.body = std.fs.cwd().readFileAlloc(allocator, assets_path, std.math.maxInt(usize)) catch {
            res.setStatus(.not_found);
            return;
        };
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
const zx = @import("../root.zig");

const Allocator = std.mem.Allocator;
const Component = zx.Component;
const Printer = zx.Printer;
const App = zx.App;
