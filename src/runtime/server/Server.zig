/// Generic Server that accepts an application context type.
/// The app context is injected into all page and layout handlers via ctx.app.
///
/// Usage:
/// ```zig
/// // With app context (pointer)
/// const AppCtx = struct { db: *Database, config: Config };
/// var app_ctx = AppCtx{ .db = &db, .config = config };
/// const server = try zx.Server(*AppCtx).init(allocator, config, &app_ctx);
///
/// // With app context (value)
/// const server = try zx.Server(AppCtx).init(allocator, config, app_ctx);
///
/// // Without app context
/// const server = try zx.Server(void).init(allocator, config, {});
/// ```
pub fn Server(comptime H: type) type {
    const AppCtxType = switch (@typeInfo(H)) {
        .@"struct" => H,
        .pointer => |ptr| ptr.child,
        .void => void,
        else => @compileError("Server app context must be a struct, pointer to struct, or void, got: " ++ @tagName(@typeInfo(H))),
    };

    return struct {
        const Self = @This();

        pub const Meta = ServerMeta;
        pub const Config = ServerConfig;
        pub const version = module_config.version_string;
        pub const jsglue_version = module_config.jsglue_version;

        allocator: std.mem.Allocator,
        meta: ServerMeta,
        handler: HandlerType,
        server: httpz.Server(*HandlerType),
        app_ctx: H,

        _is_listening: bool = false,

        const HandlerType = Handler(AppCtxType);

        pub fn init(allocator: std.mem.Allocator, config: ServerConfig, app_ctx: H) !*Self {
            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);

            self.allocator = allocator;
            self.meta = zx.meta;
            self.app_ctx = app_ctx;

            // Get pointer to app context for handler initialization
            // When H is void, pass undefined; when H is pointer, use directly; when H is value, get pointer from self
            const app_ctx_ptr: *AppCtxType = if (H == void)
                undefined
            else if (@typeInfo(H) == .pointer)
                app_ctx
            else
                &self.app_ctx;

            self.handler = try HandlerType.init(allocator, &self.meta, config.cache, app_ctx_ptr);
            errdefer self.handler.deinit();
            self.server = try httpz.Server(*HandlerType).init(allocator, config.server, &self.handler);

            // -- Routing -- //
            var router = try self.server.router(.{});

            // Static assets
            router.get("/assets/*", HandlerType.assets, .{});
            router.get("/*", HandlerType.public, .{});

            // Routes
            inline for (&zx.routes) |*route| {
                // Check if this is an API-only route (no page)
                const is_api_only = route.page == null;

                if (!is_api_only) {
                    // Page routes
                    var method_found = false;
                    var get_method_found = false;
                    if (route.page_opts) |pg_opts| {
                        inline for (pg_opts.methods) |method| {
                            method_found = true;
                            switch (method) {
                                .GET => {
                                    get_method_found = true;
                                    router.get(route.path, HandlerType.page, .{ .data = route });
                                },
                                .POST => router.post(route.path, HandlerType.page, .{ .data = route }),
                                .PUT => router.put(route.path, HandlerType.page, .{ .data = route }),
                                .DELETE => router.delete(route.path, HandlerType.page, .{ .data = route }),
                                .PATCH => router.patch(route.path, HandlerType.page, .{ .data = route }),
                                .OPTIONS => router.options(route.path, HandlerType.page, .{ .data = route }),
                                .HEAD => router.head(route.path, HandlerType.page, .{ .data = route }),
                                .CONNECT => router.connect(route.path, HandlerType.page, .{ .data = route }),
                                .TRACE => router.trace(route.path, HandlerType.page, .{ .data = route }),
                                .ALL => router.all(route.path, HandlerType.page, .{ .data = route }),
                            }
                        }
                    }

                    if (!method_found or !get_method_found) {
                        router.get(route.path, HandlerType.page, .{ .data = route });
                    }
                }

                // API routes
                if (route.route) |handlers| {
                    if (handlers.get) |_| router.get(route.path, HandlerType.api, .{ .data = route });
                    if (handlers.post) |_| router.post(route.path, HandlerType.api, .{ .data = route });
                    if (handlers.put) |_| router.put(route.path, HandlerType.api, .{ .data = route });
                    if (handlers.delete) |_| router.delete(route.path, HandlerType.api, .{ .data = route });
                    if (handlers.patch) |_| router.patch(route.path, HandlerType.api, .{ .data = route });
                    if (handlers.head) |_| router.head(route.path, HandlerType.api, .{ .data = route });
                    if (handlers.options) |_| router.options(route.path, HandlerType.api, .{ .data = route });

                    if (handlers.handler) |_| {
                        if (handlers.get == null and is_api_only) router.get(route.path, HandlerType.api, .{ .data = route });
                        if (handlers.post == null) router.post(route.path, HandlerType.api, .{ .data = route });
                        if (handlers.put == null) router.put(route.path, HandlerType.api, .{ .data = route });
                        if (handlers.delete == null) router.delete(route.path, HandlerType.api, .{ .data = route });
                        if (handlers.patch == null) router.patch(route.path, HandlerType.api, .{ .data = route });
                        if (handlers.head == null) router.head(route.path, HandlerType.api, .{ .data = route });
                        if (handlers.options == null) router.options(route.path, HandlerType.api, .{ .data = route });
                    }

                    if (handlers.custom_methods) |custom_methods| {
                        inline for (custom_methods) |custom| {
                            router.method(custom.method, route.path, HandlerType.api, .{ .data = route });
                        }
                    }
                }
            }

            // Introspect the app, this will exit the program in some cases like --introspect flag
            try self.introspect();

            return self;
        }

        pub fn deinit(self: *Self) void {
            const allocator = self.allocator;

            if (self._is_listening) {
                self.server.stop();
                self._is_listening = false;
            }
            self.server.deinit();
            self.handler.deinit();
            allocator.destroy(self);
        }

        pub fn start(self: *Self) !void {
            if (self._is_listening) return;
            self._is_listening = true;

            self.server.listen() catch |err| {
                self._is_listening = false;

                switch (err) {
                    error.AddressInUse => {
                        const is_dev = self.meta.cli_command == .dev;
                        const port = self.server.config.port.?;
                        var max_retries: u8 = 10;

                        if (is_dev) while (max_retries > 0) : (max_retries -= 1) {
                            const new_port = port + 1;
                            self.infoWithCrossedOutPort(port);
                            std.debug.print("{s}Port {d} is already in use, {s}trying with port {d}...{s}\n\n", .{ colors.yellow, port, colors.reset_all, new_port, colors.reset_all });
                            std.debug.print("To kill the port, run:\n  {s}kill -9 $(lsof -t -i:{d}){s}\n\n", .{ colors.dim, port, colors.reset_all });
                            self.server.config.port = new_port;

                            self.server.deinit();
                            var retry_server = try init(self.allocator, .{ .server = self.server.config }, self.app_ctx);
                            defer retry_server.deinit();

                            retry_server.info();
                            return retry_server.start();
                        } else {
                            std.debug.print("{s}Failed to find available port after {d} retries{s}\n", .{ colors.bold, max_retries, colors.reset_all });
                        };

                        if (!is_dev) {
                            self.infoWithCrossedOutPort(port);
                            std.debug.print("{s}Port {d} is already in use{s}\n", .{ colors.red, port, colors.reset_all });
                        }

                        std.debug.print("\nTo kill the port, run:\n  {s}kill -9 $(lsof -t -i:{d}){s}\n\n", .{ colors.dim, port, colors.reset_all });
                    },
                    else => return err,
                }
            };
        }

        /// Print the server info to the console
        /// ZX - v{version} | http://localhost:{port}
        pub fn info(self: *Self) void {
            std.debug.print("{s}ZX{s} {s}- v{s}{s} | http://localhost:{d}\n", .{ colors.bold, colors.reset_all, colors.dim, Self.version, colors.reset_all, self.server.config.port.? });
        }

        /// Print the info line with the address/port part crossed out
        fn infoWithCrossedOutPort(_: *Self, port: u16) void {
            std.debug.print(
                "{s}{s}{s}ZX{s} {s}- v{s}{s} {s} | {s}http://localhost:{d}{s}\n",
                .{
                    colors.move_up,
                    colors.reset,
                    colors.bold,
                    colors.reset_all,
                    colors.dim,
                    Self.version,
                    colors.reset_all,
                    colors.dim,
                    colors.strikethrough,
                    port,
                    colors.reset_all,
                },
            );
        }

        fn introspect(self: *Self) !void {
            var args = try std.process.argsWithAllocator(self.allocator);
            defer args.deinit();

            // --- Flags --- //
            // --introspect: Print the metadata to stdout and exit
            var is_introspect = false;
            var is_stdio = false;
            var port = self.server.config.port orelse Constant.default_port;
            var address = self.server.config.address orelse Constant.default_address;

            while (args.next()) |arg| {
                // --introspect: Print the metadata to stdout and exit
                if (std.mem.eql(u8, arg, "--introspect")) is_introspect = true;

                // --stdio: Start the server in stdio mode, where request responses will be read from stdin and written to stdout
                if (std.mem.eql(u8, arg, "--stdio")) is_stdio = true;

                // --port: Override the configured/default port
                if (std.mem.eql(u8, arg, "--port")) {
                    const port_str = args.next() orelse return error.MissingPort;
                    const port_int = std.fmt.parseInt(u16, port_str, 10) catch return error.InvalidPort;
                    port = port_int;
                }

                // --address: Override the configured/default address
                if (std.mem.eql(u8, arg, "--address")) address = args.next() orelse return error.MissingAddress;

                // --rootdir: Override the configured/default root directory
                if (std.mem.eql(u8, arg, "--rootdir")) self.meta.rootdir = args.next() orelse return error.MissingRootdir;

                // --cli-command: Override the CLI command
                if (std.mem.eql(u8, arg, "--cli-command")) {
                    const cli_command_str = args.next() orelse return error.MissingCliCommand;
                    const cli_command = std.meta.stringToEnum(ServerMeta.CliCommand, cli_command_str) orelse return error.InvalidCliCommand;
                    self.meta.cli_command = cli_command;
                }
            }

            var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
            var stdout = &stdout_writer.interface;

            var stdin_reader = std.fs.File.stdin().readerStreaming(&.{});
            var stdin = &stdin_reader.interface;
            stdin = stdin;

            // Overriding or setting default configs
            self.server.config.port = port;
            self.server.config.address = address;
            self.server.config.request.max_form_count = self.server.config.request.max_form_count orelse Constant.default_max_form_count;
            self.server.config.request.max_multiform_count = self.server.config.request.max_multiform_count orelse Constant.default_max_multiform_count;

            if (is_introspect) {
                var aw = std.Io.Writer.Allocating.init(self.allocator);
                defer aw.deinit();

                var serilizable_meta = try SerilizableAppMeta.init(self.allocator, self);
                defer serilizable_meta.deinit(self.allocator);
                try serilizable_meta.serialize(&aw.writer);

                try stdout.print("{s}\n", .{aw.written()});
                std.process.exit(0);
            }

            // Dev-only routes under /.well-known/_zx/
            if (self.meta.cli_command == .dev) {
                var router = try self.server.router(.{});
                var zx_routes = router.group("/.well-known/_zx", .{});
                zx_routes.get("/devsocket", HandlerType.devsocket, .{});
                zx_routes.get("/devscript.js", HandlerType.devscript, .{});
            }

            try stdout.flush();
        }

        pub const SerilizableAppMeta = struct {
            pub const Route = struct {
                path: []const u8,
                has_notfound: bool = false,
                is_dynamic: bool = false,
            };
            pub const Config = struct {
                server: httpz.Config,
            };

            binpath: ?[]const u8 = null,
            rootdir: ?[]const u8 = null,
            routes: []const Route,
            config: SerilizableAppMeta.Config,
            version: []const u8,
            cli_command: ?ServerMeta.CliCommand = null,

            pub fn init(allocator: std.mem.Allocator, srv: *const Self) !SerilizableAppMeta {
                var routes = try allocator.alloc(Route, srv.meta.routes.len);

                for (srv.meta.routes, 0..) |route, i| {
                    const is_dynamic = std.mem.indexOf(u8, route.path, ":") != null;
                    routes[i] = Route{
                        .path = try allocator.dupe(u8, route.path),
                        .has_notfound = route.notfound != null,
                        .is_dynamic = is_dynamic,
                    };
                }

                return SerilizableAppMeta{
                    .routes = routes,
                    .config = SerilizableAppMeta.Config{
                        .server = srv.server.config,
                    },
                    .version = Self.version,
                    .rootdir = srv.meta.rootdir,
                    .cli_command = srv.meta.cli_command,
                };
            }

            pub fn deinit(self: *SerilizableAppMeta, allocator: std.mem.Allocator) void {
                for (self.routes) |route| {
                    allocator.free(route.path);
                }
                allocator.free(self.routes);

                allocator.free(self.version);
                if (self.rootdir) |rootdir| allocator.free(rootdir);
                if (self.binpath) |binpath| allocator.free(binpath);
            }

            pub fn serialize(self: *const SerilizableAppMeta, writer: anytype) !void {
                try std.zon.stringify.serialize(self, .{
                    .whitespace = true,
                    .emit_default_optional_fields = true,
                }, writer);
            }
        };
    };
}

pub const ServerMeta = struct {
    pub const StdInput = struct {
        const Header = struct {
            name: []const u8,
            value: []const u8,
        };
        url: []const u8,
        method: zx.Request.Method,
        headers: []const Header,
        body: []const u8,
    };

    /// Route handler function type for API routes
    pub const RouteHandler = *const fn (ctx: zx.RouteContext) anyerror!void;

    /// Socket message handler function type for WebSocket connections
    /// Called for each message received from the client
    pub const SocketHandler = *const fn (
        socket: zx.Socket,
        message: []const u8,
        message_type: zx.SocketMessageType,
        upgrade_data: ?[]const u8,
        allocator: std.mem.Allocator,
        arena: std.mem.Allocator,
    ) anyerror!void;

    /// Socket open handler function type (optional)
    /// Called once when the WebSocket connection is established
    pub const SocketOpenHandler = *const fn (
        socket: zx.Socket,
        upgrade_data: ?[]const u8,
        allocator: std.mem.Allocator,
        arena: std.mem.Allocator,
    ) anyerror!void;

    /// Socket close handler function type (optional)
    /// Called once when the WebSocket connection is closed
    pub const SocketCloseHandler = *const fn (
        socket: zx.Socket,
        upgrade_data: ?[]const u8,
        allocator: std.mem.Allocator,
    ) void;

    /// Custom method entry for non-standard HTTP methods
    pub const CustomMethod = struct {
        method: []const u8,
        handler: RouteHandler,
    };

    /// Struct containing all HTTP method handlers for an API route
    pub const RouteHandlers = struct {
        handler: ?RouteHandler = null, // Catch-all undefined standard HTTP method
        get: ?RouteHandler = null,
        post: ?RouteHandler = null,
        put: ?RouteHandler = null,
        delete: ?RouteHandler = null,
        patch: ?RouteHandler = null,
        head: ?RouteHandler = null,
        options: ?RouteHandler = null,
        custom_methods: ?[]const CustomMethod = null, // Arbitrary uppercase methods
        socket: ?SocketHandler = null,
        socket_open: ?SocketOpenHandler = null,
        socket_close: ?SocketCloseHandler = null,
    };

    // Standard HTTP methods to exclude from custom detection
    fn isStandardMethod(name: []const u8) bool {
        const standard_methods = [_][]const u8{ "Route", "Socket", "SocketOpen", "SocketClose", "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS" };
        for (standard_methods) |std_method| {
            if (std.mem.eql(u8, name, std_method)) return true;
        }
        return false;
    }

    fn isAllUppercase(name: []const u8) bool {
        if (name.len == 0) return false;
        for (name) |c| if (!std.ascii.isUpper(c)) return false;
        return true;
    }

    /// Comptime function to build RouteHandlers from a route module
    /// Optionally takes a page module to validate for method conflicts
    pub fn route(comptime T: type, comptime PageModule: ?type) RouteHandlers {
        // Validate for method conflicts when page module is provided
        if (PageModule) |P| {
            const page_methods = if (@hasDecl(P, "options") and @hasField(@TypeOf(P.options), "methods"))
                P.options.methods
            else
                &[_]zx.PageMethod{.GET};

            // Check for specific method conflicts
            inline for (page_methods) |method| {
                const method_name = @tagName(method);
                if (@hasDecl(T, method_name)) {
                    @compileError("route.zig cannot define " ++ method_name ++ " handler when page.zx handles it. Remove the method from route.zig or page_opts.methods.");
                }
            }

            // Check for Route() catch-all conflict when page handles non-GET methods
            // Route() would intercept methods that page.zx should handle
            if (@hasDecl(T, "Route")) {
                inline for (page_methods) |method| {
                    if (method != .GET) {
                        @compileError("route.zig cannot define Route() catch-all handler when page.zx handles " ++ @tagName(method) ++ ". Use specific method handlers (POST, PUT, etc.) in route.zig instead.");
                    }
                }
            }
        }

        // Count custom methods first
        comptime var custom_count: usize = 0;
        const decls = @typeInfo(T).@"struct".decls;
        for (decls) |decl| {
            if (!isStandardMethod(decl.name) and isAllUppercase(decl.name)) {
                const field = @field(T, decl.name);
                const FieldType = @TypeOf(field);
                if (@typeInfo(FieldType) == .@"fn") {
                    custom_count += 1;
                }
            }
        }

        // Build custom methods array as const
        const custom_methods = comptime blk: {
            var methods: [custom_count]CustomMethod = undefined;
            var idx: usize = 0;
            for (decls) |decl| {
                if (!isStandardMethod(decl.name) and isAllUppercase(decl.name)) {
                    const field = @field(T, decl.name);
                    const FieldType = @TypeOf(field);
                    if (@typeInfo(FieldType) == .@"fn") {
                        methods[idx] = .{
                            .method = decl.name,
                            .handler = wrapRoute(field),
                        };
                        idx += 1;
                    }
                }
            }
            break :blk methods;
        };

        return .{
            .handler = if (@hasDecl(T, "Route")) wrapRoute(T.Route) else null,
            .get = if (@hasDecl(T, "GET")) wrapRoute(T.GET) else null,
            .post = if (@hasDecl(T, "POST")) wrapRoute(T.POST) else null,
            .put = if (@hasDecl(T, "PUT")) wrapRoute(T.PUT) else null,
            .delete = if (@hasDecl(T, "DELETE")) wrapRoute(T.DELETE) else null,
            .patch = if (@hasDecl(T, "PATCH")) wrapRoute(T.PATCH) else null,
            .head = if (@hasDecl(T, "HEAD")) wrapRoute(T.HEAD) else null,
            .options = if (@hasDecl(T, "OPTIONS")) wrapRoute(T.OPTIONS) else null,
            .custom_methods = if (custom_count > 0) &custom_methods else null,
            .socket = if (@hasDecl(T, "Socket")) wrapSocket(T.Socket) else null,
            .socket_open = if (@hasDecl(T, "SocketOpen")) wrapSocketOpen(T.SocketOpen) else null,
            .socket_close = if (@hasDecl(T, "SocketClose")) wrapSocketClose(T.SocketClose) else null,
        };
    }

    /// Wrapper to allow socket message handlers to return void or !void
    /// Supports both SocketContext (simple) and SocketCtx(T) (with custom data)
    fn wrapSocket(comptime socketFn: anytype) SocketHandler {
        const FnInfo = @typeInfo(@TypeOf(socketFn)).@"fn";
        const R = FnInfo.return_type.?;
        const CtxType = FnInfo.params[0].type.?;
        const DataType = @TypeOf(@as(CtxType, undefined).data);

        return struct {
            fn wrapper(socket: zx.Socket, message: []const u8, message_type: zx.SocketMessageType, upgrade_data: ?[]const u8, allocator: std.mem.Allocator, arena: std.mem.Allocator) anyerror!void {
                const data: DataType = if (upgrade_data) |bytes|
                    std.mem.bytesToValue(DataType, bytes[0..@sizeOf(DataType)])
                else
                    std.mem.zeroes(DataType);

                const ctx = CtxType{
                    .socket = socket,
                    .message = message,
                    .message_type = message_type,
                    .data = data,
                    .allocator = allocator,
                    .arena = arena,
                };
                if (R == void) {
                    socketFn(ctx);
                } else {
                    try socketFn(ctx);
                }
            }
        }.wrapper;
    }

    /// Wrapper for SocketOpen handlers
    fn wrapSocketOpen(comptime socketOpenFn: anytype) SocketOpenHandler {
        const FnInfo = @typeInfo(@TypeOf(socketOpenFn)).@"fn";
        const R = FnInfo.return_type.?;
        const CtxType = FnInfo.params[0].type.?;
        const DataType = @TypeOf(@as(CtxType, undefined).data);

        return struct {
            fn wrapper(socket: zx.Socket, upgrade_data: ?[]const u8, allocator: std.mem.Allocator, arena: std.mem.Allocator) anyerror!void {
                const data: DataType = if (upgrade_data) |bytes|
                    std.mem.bytesToValue(DataType, bytes[0..@sizeOf(DataType)])
                else
                    std.mem.zeroes(DataType);

                const ctx = CtxType{
                    .socket = socket,
                    .data = data,
                    .allocator = allocator,
                    .arena = arena,
                };
                if (R == void) {
                    socketOpenFn(ctx);
                } else {
                    try socketOpenFn(ctx);
                }
            }
        }.wrapper;
    }

    /// Wrapper for SocketClose handlers
    fn wrapSocketClose(comptime socketCloseFn: anytype) SocketCloseHandler {
        const CtxType = @typeInfo(@TypeOf(socketCloseFn)).@"fn".params[0].type.?;
        const DataType = @TypeOf(@as(CtxType, undefined).data);

        return struct {
            fn wrapper(socket: zx.Socket, upgrade_data: ?[]const u8, allocator: std.mem.Allocator) void {
                const data: DataType = if (upgrade_data) |bytes|
                    std.mem.bytesToValue(DataType, bytes[0..@sizeOf(DataType)])
                else
                    std.mem.zeroes(DataType);

                const ctx = CtxType{
                    .socket = socket,
                    .data = data,
                    .allocator = allocator,
                    .arena = allocator,
                };
                socketCloseFn(ctx);
            }
        }.wrapper;
    }

    /// Wrapper to allow routes to return void or !void.
    /// Handles both zx.RouteContext (void app/state) and zx.RouteCtx(AppCtx, State) (custom context).
    fn wrapRoute(comptime routeFn: anytype) RouteHandler {
        const FnInfo = @typeInfo(@TypeOf(routeFn)).@"fn";
        const R = FnInfo.return_type.?;
        const CtxType = FnInfo.params[0].type.?;

        return struct {
            fn wrapper(ctx: zx.RouteContext) anyerror!void {
                if (CtxType == zx.RouteContext) {
                    // Standard RouteContext, pass directly
                    if (R == void) {
                        routeFn(ctx);
                    } else {
                        try routeFn(ctx);
                    }
                } else {
                    // Custom context type - cast app pointer and state
                    const AppType = @TypeOf(@as(CtxType, undefined).app);
                    const app: AppType = if (AppType == void) {} else if (AppType == ?*const anyopaque)
                        ctx.app
                    else if (@typeInfo(AppType) == .pointer)
                        @ptrCast(@alignCast(ctx.app))
                    else
                        (@as(*const AppType, @ptrCast(@alignCast(ctx.app)))).*;

                    // Cast state from type-erased pointer
                    const StateType = @TypeOf(@as(CtxType, undefined).state);
                    const state: StateType = if (StateType == void) {} else if (ctx._state_ptr) |ptr|
                        (@as(*const StateType, @ptrCast(@alignCast(ptr)))).*
                    else
                        std.mem.zeroes(StateType);

                    const custom_ctx = CtxType{
                        .app = app,
                        .state = state,
                        .request = ctx.request,
                        .response = ctx.response,
                        .socket = ctx.socket,
                        .allocator = ctx.allocator,
                        .arena = ctx.arena,
                    };
                    if (R == void) {
                        routeFn(custom_ctx);
                    } else {
                        try routeFn(custom_ctx);
                    }
                }
            }
        }.wrapper;
    }

    /// Proxy handler function type - called before page/route handlers
    pub const ProxyHandler = *const fn (ctx: *zx.ProxyContext) anyerror!void;

    /// Wrapper to allow proxy handlers to return void or !void
    fn wrapProxy(comptime proxyFn: anytype) ProxyHandler {
        const R = @typeInfo(@TypeOf(proxyFn)).@"fn".return_type.?;
        return struct {
            fn wrapper(ctx: *zx.ProxyContext) anyerror!void {
                if (R == void) {
                    proxyFn(ctx);
                } else {
                    try proxyFn(ctx);
                }
            }
        }.wrapper;
    }

    /// Comptime function to extract global Proxy handler from a proxy module (cascades to child routes)
    pub fn proxy(comptime T: type) ?ProxyHandler {
        if (@hasDecl(T, "Proxy")) {
            return wrapProxy(T.Proxy);
        }
        return null;
    }

    /// Comptime function to extract PageProxy handler from a proxy module (does NOT cascade)
    pub fn pageProxy(comptime T: type) ?ProxyHandler {
        if (@hasDecl(T, "PageProxy")) {
            return wrapProxy(T.PageProxy);
        }
        return null;
    }

    /// Comptime function to extract RouteProxy handler from a proxy module (does NOT cascade)
    pub fn routeProxy(comptime T: type) ?ProxyHandler {
        if (@hasDecl(T, "RouteProxy")) {
            return wrapProxy(T.RouteProxy);
        }
        return null;
    }

    /// Page handler function type
    pub const PageHandler = *const fn (ctx: zx.PageContext) anyerror!Component;

    /// Layout handler function type
    pub const LayoutHandler = *const fn (ctx: zx.LayoutContext, component: Component) Component;

    /// Comptime function to wrap a page module's Page function.
    /// Handles both zx.PageContext (void app/state) and zx.PageCtx(AppCtx, State) (custom context).
    /// The app context and state are read from type-erased pointers and cast to the appropriate types.
    pub fn page(comptime T: type) PageHandler {
        const pageFn = T.Page;
        const FnType = @TypeOf(pageFn);
        const fn_info = @typeInfo(FnType).@"fn";
        const CtxType = fn_info.params[0].type.?;
        const R = fn_info.return_type.?;

        return struct {
            fn wrapper(ctx: zx.PageContext) anyerror!Component {
                // If page expects standard PageContext, pass it directly
                if (CtxType == zx.PageContext) {
                    if (R == Component) {
                        return pageFn(ctx);
                    } else {
                        return try pageFn(ctx);
                    }
                } else {
                    // Page expects custom context type - cast app pointer and state to correct types
                    // ctx.app for void is ?*const anyopaque (type-erased pointer)
                    const AppType = @TypeOf(@as(CtxType, undefined).app);
                    const app: AppType = if (AppType == void) {} else if (AppType == ?*const anyopaque)
                        ctx.app
                    else if (@typeInfo(AppType) == .pointer)
                        @ptrCast(@alignCast(ctx.app))
                    else
                        (@as(*const AppType, @ptrCast(@alignCast(ctx.app)))).*;

                    // Cast state from type-erased pointer
                    const StateType = @TypeOf(@as(CtxType, undefined).state);
                    const state: StateType = if (StateType == void) {} else if (ctx._state_ptr) |ptr|
                        (@as(*const StateType, @ptrCast(@alignCast(ptr)))).*
                    else
                        std.mem.zeroes(StateType);

                    const custom_ctx = CtxType{
                        .app = app,
                        .state = state,
                        .request = ctx.request,
                        .response = ctx.response,
                        .allocator = ctx.allocator,
                        .arena = ctx.arena,
                    };
                    if (R == Component) {
                        return pageFn(custom_ctx);
                    } else {
                        return try pageFn(custom_ctx);
                    }
                }
            }
        }.wrapper;
    }

    /// Comptime function to wrap a layout module's Layout function.
    /// Handles both zx.LayoutContext (void app/state) and zx.LayoutCtx(AppCtx, State) (custom context).
    pub fn layout(comptime T: type) LayoutHandler {
        const layoutFn = T.Layout;
        const FnType = @TypeOf(layoutFn);
        const fn_info = @typeInfo(FnType).@"fn";
        const CtxType = fn_info.params[0].type.?;

        return struct {
            fn wrapper(ctx: zx.LayoutContext, component: Component) Component {
                // If layout expects standard LayoutContext, pass it directly
                if (CtxType == zx.LayoutContext) {
                    return layoutFn(ctx, component);
                } else {
                    // Layout expects custom context type - cast app pointer and state to correct types
                    // ctx.app for void is ?*const anyopaque (type-erased pointer)
                    const AppType = @TypeOf(@as(CtxType, undefined).app);
                    const app: AppType = if (AppType == void) {} else if (AppType == ?*const anyopaque)
                        ctx.app
                    else if (@typeInfo(AppType) == .pointer)
                        @ptrCast(@alignCast(ctx.app))
                    else
                        (@as(*const AppType, @ptrCast(@alignCast(ctx.app)))).*;

                    // Cast state from type-erased pointer
                    const StateType = @TypeOf(@as(CtxType, undefined).state);
                    const state: StateType = if (StateType == void) {} else if (ctx._state_ptr) |ptr|
                        (@as(*const StateType, @ptrCast(@alignCast(ptr)))).*
                    else
                        std.mem.zeroes(StateType);

                    const custom_ctx = CtxType{
                        .app = app,
                        .state = state,
                        .request = ctx.request,
                        .response = ctx.response,
                        .allocator = ctx.allocator,
                        .arena = ctx.arena,
                    };
                    return layoutFn(custom_ctx, component);
                }
            }
        }.wrapper;
    }

    pub const Route = struct {
        path: []const u8,
        page: ?PageHandler = null,
        layout: ?LayoutHandler = null,
        notfound: ?*const fn (ctx: zx.NotFoundContext) Component = null,
        @"error": ?*const fn (ctx: zx.ErrorContext) Component = null,
        page_opts: ?zx.PageOptions = null,
        layout_opts: ?zx.LayoutOptions = null,
        notfound_opts: ?zx.NotFoundOptions = null,
        error_opts: ?zx.ErrorOptions = null,
        route: ?RouteHandlers = null,
        route_opts: ?zx.RouteOptions = null,
        proxy: ?ProxyHandler = null,
        page_proxy: ?ProxyHandler = null,
        route_proxy: ?ProxyHandler = null,
    };
    pub const CliCommand = enum { dev, serve, @"export" };

    routes: []const Route,
    rootdir: []const u8,
    cli_command: ?CliCommand = null,
};

pub const ServerConfig = struct {
    server: httpz.Config,
    cache: CacheConfig = .{},
};

const std = @import("std");
const builtin = @import("builtin");
const httpz = @import("httpz");
const cachez = @import("cachez");
const zx = @import("../../root.zig");
const module_config = @import("zx_info");
const Constant = @import("../../constant.zig");
const Handler = @import("handler.zig").Handler;
const CacheConfig = @import("handler.zig").CacheConfig;

const Allocator = std.mem.Allocator;
const Component = zx.Component;
const log = std.log.scoped(.app);

const colors = struct {
    const move_up = "\x1b[1A";
    const reset = "\r";
    const bold = "\x1b[1m";
    const dim = "\x1b[2m";
    const strikethrough = "\x1b[9m";
    const reset_all = "\x1b[0m";
    const yellow = "\x1b[33m";
    const red = "\x1b[31m";
    const blink = "\x1b[5m";
};
