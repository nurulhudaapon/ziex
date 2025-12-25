pub const App = struct {
    pub const ExportType = enum { static };
    pub const ExportOptions = struct {
        type: ExportType,
        outdir: ?[]const u8 = "dist",
    };

    pub const Meta = struct {
        pub const Route = struct {
            path: []const u8,
            page: *const fn (ctx: zx.PageContext) Component,
            layout: ?*const fn (ctx: zx.LayoutContext, component: Component) Component = null,
            options: ?zx.PageOptions = null,
        };
        pub const CliCommand = enum { dev, serve, @"export" };

        routes: []const Route,
        rootdir: []const u8,
        cli_command: ?CliCommand = null,
    };
    pub const Config = struct {
        server: httpz.Config,
        meta: Meta,
        cache: CacheConfig = .{},
    };

    pub const version = module_config.version_string;

    allocator: std.mem.Allocator,
    meta: Meta,
    handler: Handler,
    server: httpz.Server(*Handler),

    _is_listening: bool = false,

    pub fn init(allocator: std.mem.Allocator, config: Config) !*App {
        const app = try allocator.create(App);
        errdefer allocator.destroy(app);

        app.allocator = allocator;
        app.meta = config.meta;
        app.handler = try Handler.init(allocator, &app.meta, config.cache);
        errdefer app.handler.deinit();
        app.server = try httpz.Server(*Handler).init(allocator, config.server, &app.handler);

        // -- Routing -- //
        var router = try app.server.router(.{});

        // Static assets
        router.get("/assets/*", Handler.assets, .{});
        router.get("/*", Handler.public, .{});

        // Routes
        for (config.meta.routes) |*route|
            router.get(route.path, Handler.page, .{ .data = route });

        // Introspect the app, this will exit the program in some cases like --introspect flag
        try app.introspect();

        return app;
    }

    pub fn deinit(self: *App) void {
        const allocator = self.allocator;

        if (self._is_listening) {
            self.server.stop();
            self._is_listening = false;
        }
        self.server.deinit();
        self.handler.deinit();
        allocator.destroy(self);
    }

    pub fn start(self: *App) !void {
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
                        var retry_app = try init(self.allocator, .{ .server = self.server.config, .meta = self.meta });
                        defer retry_app.deinit();

                        retry_app.info();
                        return retry_app.start();
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

    /// Print the app info to the console
    /// ZX - v{version} | http://localhost:{port}
    pub fn info(self: *App) void {
        std.debug.print("{s}ZX{s} {s}- v{s}{s} | http://localhost:{d}\n", .{ colors.bold, colors.reset_all, colors.dim, App.version, colors.reset_all, self.server.config.port.? });
    }

    /// Print the info line with the address/port part crossed out
    fn infoWithCrossedOutPort(_: *App, port: u16) void {
        std.debug.print(
            "{s}{s}{s}ZX{s} {s}- v{s}{s} {s} | {s}http://localhost:{d}{s}\n",
            .{
                colors.move_up,
                colors.reset,
                colors.bold,
                colors.reset_all,
                colors.dim,
                App.version,
                colors.reset_all,
                colors.dim,
                colors.strikethrough,
                port,
                colors.reset_all,
            },
        );
    }

    fn introspect(self: *App) !void {
        var args = try std.process.argsWithAllocator(self.allocator);
        defer args.deinit();

        // --- Flags --- //
        // --introspect: Print the metadata to stdout and exit
        var is_introspect = false;
        var port = self.server.config.port orelse Constant.default_port;
        var address = self.server.config.address orelse Constant.default_address;

        while (args.next()) |arg| {
            // --introspect: Print the metadata to stdout and exit
            if (std.mem.eql(u8, arg, "--introspect")) is_introspect = true;

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
                const cli_command = std.meta.stringToEnum(Meta.CliCommand, cli_command_str) orelse return error.InvalidCliCommand;
                self.meta.cli_command = cli_command;

                // log.debug("CLI command: {s}", .{cli_command_str});
            }
        }

        var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
        var stdout = &stdout_writer.interface;

        // Overriding or setting default configs
        self.server.config.port = port;
        self.server.config.address = address;
        self.server.config.request.max_form_count = self.server.config.request.max_form_count orelse Constant.default_max_form_count;

        if (is_introspect) {
            var aw = std.Io.Writer.Allocating.init(self.allocator);
            defer aw.deinit();

            var serilizable_meta = try SerilizableAppMeta.init(self.allocator, self);
            defer serilizable_meta.deinit(self.allocator);
            try serilizable_meta.serialize(&aw.writer);

            try stdout.print("{s}\n", .{aw.written()});
            std.process.exit(0);
        }

        if (self.meta.cli_command == .dev) {
            var router = try self.server.router(.{});
            router.get("/_zx/devsocket", Handler.devsocket, .{});
        }

        try stdout.flush();
    }

    pub const SerilizableAppMeta = struct {
        pub const Route = struct {
            path: []const u8,
        };
        pub const Config = struct {
            server: httpz.Config,
        };

        binpath: ?[]const u8 = null,
        rootdir: ?[]const u8 = null,
        routes: []const Route,
        config: SerilizableAppMeta.Config,
        version: []const u8,
        cli_command: ?App.Meta.CliCommand = null,

        pub fn init(allocator: std.mem.Allocator, app: *const App) !SerilizableAppMeta {
            var routes = try allocator.alloc(Route, app.meta.routes.len);

            for (app.meta.routes, 0..) |route, i| {
                routes[i] = Route{
                    .path = try allocator.dupe(u8, route.path),
                };
            }

            return SerilizableAppMeta{
                .routes = routes,
                .config = SerilizableAppMeta.Config{
                    .server = app.server.config,
                },
                .version = App.version,
                .rootdir = app.meta.rootdir,
                .cli_command = app.meta.cli_command,
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

const std = @import("std");
const builtin = @import("builtin");
const httpz = @import("httpz");
const cachez = @import("cachez");
const zx = @import("root.zig");
const module_config = @import("zx_info");
const Constant = @import("./constant.zig");
const Handler = @import("./app/handler.zig").Handler;
const CacheConfig = @import("./app/handler.zig").CacheConfig;

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
