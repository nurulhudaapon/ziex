pub fn register(writer: *std.Io.Writer, reader: *std.Io.Reader, allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(writer, reader, allocator, .{
        .name = "export",
        .description = "Export the site to a static HTML directory",
    }, @"export");

    try cmd.addFlag(outdir_flag);
    try cmd.addFlag(flag.binpath_flag);
    try cmd.addFlag(build_args_flag);

    return cmd;
}

const outdir_flag = zli.Flag{
    .name = "outdir",
    .shortcut = "o",
    .description = "Output directory",
    .type = .String,
    .default_value = .{ .String = "dist" },
};

const build_args_flag = zli.Flag{
    .name = "build-args",
    .shortcut = null,
    .description = "Additional arguments to pass to zig build (e.g., -Doptimize=ReleaseFast)",
    .type = .String,
    .default_value = .{ .String = "--release=small" },
};

const DEFAULT_INSTALL_PREFIX = "zig-out";

fn @"export"(ctx: zli.CommandContext) !void {
    const app = AppContext.from(&ctx);
    const io = app.io;
    const outdir = ctx.flag("outdir", []const u8);

    var build_argv = std.ArrayList([]const u8).empty;
    defer build_argv.deinit(ctx.allocator);
    try build_argv.appendSlice(ctx.allocator, &.{ cli_options.zig_exe, "build" });
    try build_argv.appendSlice(ctx.allocator, &.{"-Dcli-command=export"});

    var i_build_args = std.mem.splitSequence(u8, ctx.flag("build-args", []const u8), " ");
    while (i_build_args.next()) |arg| {
        const trimmed_arg = std.mem.trim(u8, arg, " ");
        if (std.mem.eql(u8, trimmed_arg, "")) continue;
        try build_argv.append(ctx.allocator, trimmed_arg);
    }

    var build_proc = try std.process.spawn(io, .{
        .argv = build_argv.items,
        .environ_map = app.environ_map,
    });
    switch (try build_proc.wait(io)) {
        .exited => |code| if (code != 0) {
            try ctx.writer.print("Failed to build the ZX executable for export (exit {d})!\n", .{code});
            return;
        },
        else => {
            try ctx.writer.print("Failed to build the ZX executable for export!\n", .{});
            return;
        },
    }

    // Read install manifest for executable path and page routes.
    const manifest_path = try std.fs.path.join(ctx.allocator, &.{ DEFAULT_INSTALL_PREFIX, "manifest", "app.zon" });
    defer ctx.allocator.free(manifest_path);

    const manifest_source = std.Io.Dir.cwd().readFileAlloc(io, manifest_path, ctx.allocator, .unlimited) catch |err| {
        try ctx.writer.print("Failed to read manifest at {s}: {}\n", .{ manifest_path, err });
        return;
    };
    defer ctx.allocator.free(manifest_source);

    const manifest_source_z = try ctx.allocator.dupeSentinel(u8, manifest_source, 0);
    defer ctx.allocator.free(manifest_source_z);

    const manifest = std.zon.parse.fromSliceAlloc(ManifestApp, ctx.allocator, manifest_source_z, null, .{ .ignore_unknown_fields = true }) catch |err| {
        try ctx.writer.print("Failed to parse manifest at {s}: {}\n", .{ manifest_path, err });
        return;
    };
    defer std.zon.parse.free(ctx.allocator, manifest);

    const binpath_flag = ctx.flag("binpath", []const u8);
    const exe_path = util.resolveExePath(io, ctx.allocator, DEFAULT_INSTALL_PREFIX, binpath_flag) catch {
        try ctx.writer.print("Run \x1b[34mzig build\x1b[0m to build the ZX executable first!\n", .{});
        return;
    };
    defer ctx.allocator.free(exe_path);

    const port = DevServer.findFreePort(io) catch 3000;
    const port_str = try std.fmt.allocPrint(ctx.allocator, "{d}", .{port});
    defer ctx.allocator.free(port_str);
    const host = "0.0.0.0";

    const environ_map = app.environ_map;
    try environ_map.put("ZIEX_INNER_PORT", port_str);

    try environ_map.put("ZIEX_ROOT_DIR", DEFAULT_INSTALL_PREFIX);

    log.debug("Spawning export server exe={s} port={d} rootdir={s}", .{ exe_path, port, DEFAULT_INSTALL_PREFIX });

    var app_child = try std.process.spawn(io, .{
        .argv = &.{ exe_path, "--cli-command", "export" },
        .environ_map = environ_map,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    defer {
        app_child.kill(io);
    }
    errdefer {
        app_child.kill(io);
    }

    var printer = tui.Printer.init(ctx.allocator, .{ .file_path_mode = .flat, .file_tree_max_depth = 1 });
    defer printer.deinit();

    printer.header("{s} Building static ZX site!", .{tui.Printer.emoji("○")});
    printer.info("{s}", .{outdir});
    // delete the outdir if it exists
    // std.Io.Dir.cwd().deleteTree(outdir) catch |err| switch (err) {
    //     else => {},
    // };

    const staticdir = try std.fs.path.join(ctx.allocator, &.{ DEFAULT_INSTALL_PREFIX, "static" });
    defer ctx.allocator.free(staticdir);

    log.debug("Building static ZX site! binpath={s} rootdir={s}", .{ exe_path, DEFAULT_INSTALL_PREFIX });
    log.debug("Port: {d}, Outdir: {s}, Staticdir: {s}", .{ port, outdir, staticdir });

    log.debug("Processing routes! {d}", .{manifest.routes.len});

    var connection_retries: u32 = 0;

    process_block: while (true) {
        for (manifest.routes) |entry| {
            const route = Server.SerilizableAppMeta.Route{
                .path = entry.path,
                .has_notfound = entry.notfound_import != null,
                .is_dynamic = std.mem.indexOf(u8, entry.path, ":") != null or std.mem.indexOf(u8, entry.path, "*") != null,
            };

            log.debug("Export route {s} dynamic={} notfound={}", .{ route.path, route.is_dynamic, route.has_notfound });

            if (route.is_dynamic) {
                log.debug("Fetching static params for {s}", .{route.path});
                const static_params = fetchStaticParams(io, ctx.allocator, host, port, route.path) catch |err| {
                    if (err == error.ConnectionRefused) {
                        try waitForServerRetry(io, &connection_retries, route.path, "static-params", &app_child);
                        continue :process_block;
                    }
                    log.warn("Failed to fetch static params for {s}: {any}", .{ route.path, err });
                    continue;
                };
                defer static_params.deinit();
                connection_retries = 0;

                log.debug("Static params for {s}: {d} paths", .{ route.path, static_params.items.len });

                if (static_params.items.len > 0) {
                    for (static_params.items) |expanded_path| {
                        const expanded_route = Server.SerilizableAppMeta.Route{
                            .path = expanded_path,
                            .has_notfound = route.has_notfound,
                            .is_dynamic = false,
                        };
                        processRoute(io, ctx.allocator, host, port, expanded_route, outdir, &printer, .page) catch |err| {
                            if (err == error.ConnectionRefused) {
                                try waitForServerRetry(io, &connection_retries, expanded_route.path, "page", &app_child);
                                continue :process_block;
                            }
                            return err;
                        };
                    }
                } else {
                    log.debug("No static params for dynamic route: {s}", .{route.path});
                }
            } else {
                processRoute(io, ctx.allocator, host, port, route, outdir, &printer, .page) catch |err| {
                    if (err == error.ConnectionRefused) {
                        try waitForServerRetry(io, &connection_retries, route.path, "page", &app_child);
                        continue :process_block;
                    }
                    return err;
                };
            }
            connection_retries = 0;

            // Also export 404.html for routes that have notfound handler
            if (route.has_notfound) {
                processRoute(io, ctx.allocator, host, port, route, outdir, &printer, .notfound) catch |err| {
                    if (err == error.ConnectionRefused) {
                        try waitForServerRetry(io, &connection_retries, route.path, "notfound", &app_child);
                        continue :process_block;
                    }
                    return err;
                };
            }
        }
        break;
    }

    log.debug("Copying public directory! {s}", .{outdir});

    util.copydirs(io, ctx.allocator, staticdir, &.{"."}, outdir, false, &printer) catch |err| {
        std.log.err("Failed to copy public directory: {any}", .{err});
        return err;
    };

    // std.Io.Dir.cwd().deleteTree(io, DEFAULT_INSTALL_PREFIX) catch |err| {
    //     log.warn("Failed to delete temp files: {any}", .{err});
    // };
}

const MAX_CONNECTION_RETRIES: u32 = 3_000;

fn waitForServerRetry(
    io: std.Io,
    retries: *u32,
    route_path: []const u8,
    kind: []const u8,
    app_child: *std.process.Child,
) !void {
    retries.* += 1;
    const n = retries.*;
    if (n <= 5 or n % 100 == 0) {
        log.debug("Connection refused for {s} ({s}), retry {d}", .{ route_path, kind, n });
    }

    if (!isChildAlive(app_child)) {
        if (app_child.wait(io)) |term| {
            logChildTermination(term);
        } else |err| {
            log.err("Export server process exited before becoming reachable ({any})", .{err});
        }
        return error.ExportServerExited;
    }

    if (n >= MAX_CONNECTION_RETRIES) {
        log.err(
            "Export server never became reachable for {s} ({s}) after {d} retries",
            .{ route_path, kind, n },
        );
        return error.ExportServerUnavailable;
    }
    std.Io.sleep(io, .fromMilliseconds(10), .awake) catch {};
}

fn isChildAlive(child: *std.process.Child) bool {
    // On non-POSIX targets we keep retry behavior unchanged.
    if (builtin.os.tag == .windows) return true;
    const pid = child.id orelse return true;
    std.posix.kill(pid, @enumFromInt(0)) catch |err| switch (err) {
        error.ProcessNotFound => return false,
        else => return true,
    };
    return true;
}

fn logChildTermination(term: std.process.Child.Term) void {
    switch (term) {
        .exited => |code| log.err("Export server exited before startup (exit {d})", .{code}),
        .signal => |sig| log.err("Export server terminated by signal {d} before startup", .{@intFromEnum(sig)}),
        else => |v| log.err("Export server terminated before startup: {any}", .{v}),
    }
}

const ExportType = enum { page, notfound };

const StaticParamsResult = struct {
    items: []const []const u8,
    allocator: ?std.mem.Allocator = null,

    fn deinit(self: StaticParamsResult) void {
        if (self.allocator) |alloc| {
            for (self.items) |path| {
                alloc.free(path);
            }
            alloc.free(self.items);
        }
    }
};

fn processRoute(
    io: std.Io,
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    route: Server.SerilizableAppMeta.Route,
    outdir: []const u8,
    printer: *tui.Printer,
    export_type: ExportType,
) !void {
    // Fetch the route's HTML content
    var client = std.http.Client{ .allocator = allocator, .io = io };
    defer client.deinit();

    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();

    const effective_host = if (std.mem.eql(u8, host, "0.0.0.0")) "127.0.0.1" else host;
    const url = try std.fmt.allocPrint(allocator, "http://{s}:{d}{s}", .{ effective_host, port, route.path });
    defer allocator.free(url);

    var extra_headers: [1]std.http.Header = .{.{ .name = "x-zx-export-notfound", .value = "true" }};

    log.debug("Fetching {s} kind={s} url={s}", .{ route.path, @tagName(export_type), url });

    const result = try client.fetch(.{
        .method = .GET,
        .location = .{ .url = url },
        .extra_headers = if (export_type == .notfound) &extra_headers else &.{},
        .response_writer = &aw.writer,
    });

    const response_text = aw.written();
    log.debug("Fetched {s} kind={s} status={} body_len={d}", .{ route.path, @tagName(export_type), result.status, response_text.len });

    // Determine the output file path
    var file_path: []const u8 = undefined;
    var file_path_owned: ?[]u8 = null;
    defer if (file_path_owned) |fp| allocator.free(fp);

    if (export_type == .notfound) {
        // For 404 pages, output as 404.html in the route's directory
        if (std.mem.eql(u8, route.path, "/")) {
            file_path = "404.html";
        } else {
            // For non-root paths like /docs, output as docs/404.html
            var path_components = std.ArrayList([]const u8).empty;
            defer path_components.deinit(allocator);

            var path_iter = std.mem.splitScalar(u8, route.path, '/');
            while (path_iter.next()) |component| {
                if (component.len > 0) {
                    try path_components.append(allocator, component);
                }
            }
            try path_components.append(allocator, "404.html");
            file_path_owned = try std.fs.path.join(allocator, path_components.items);
            file_path = file_path_owned.?;
        }
    } else if (std.mem.eql(u8, route.path, "/")) {
        // For root path "/", use "index.html"
        file_path = "index.html";
    } else {
        // Split the URL path by "/" to get path components
        // Skip the first empty component (from leading "/")
        var path_components = std.ArrayList([]const u8).empty;
        defer path_components.deinit(allocator);

        var path_iter = std.mem.splitScalar(u8, route.path, '/');
        while (path_iter.next()) |component| {
            if (component.len > 0) {
                try path_components.append(allocator, component);
            }
        }

        if (route.path[route.path.len - 1] == '/') {
            // For paths ending in "/", create directory/index.html structure
            try path_components.append(allocator, "index.html");
            file_path_owned = try std.fs.path.join(allocator, path_components.items);
            file_path = file_path_owned.?;
        } else {
            // Get the last component (filename)
            const last_component = path_components.items[path_components.items.len - 1];
            // Add .html extension if it doesn't have one
            if (std.fs.path.extension(last_component).len == 0) {
                const last_with_ext = try std.fmt.allocPrint(allocator, "{s}.html", .{last_component});
                defer allocator.free(last_with_ext);

                // Replace the last component with the one that has .html extension
                _ = path_components.pop();
                try path_components.append(allocator, last_with_ext);
                file_path_owned = try std.fs.path.join(allocator, path_components.items);
                file_path = file_path_owned.?;
            } else {
                // Path already has an extension, join all components
                file_path_owned = try std.fs.path.join(allocator, path_components.items);
                file_path = file_path_owned.?;
            }
        }
    }

    const output_path = try std.fs.path.join(allocator, &.{ outdir, file_path });
    defer allocator.free(output_path);

    // Create parent directories if they don't exist
    const output_dir = std.fs.path.dirname(output_path);
    if (output_dir) |dir| {
        try std.Io.Dir.cwd().createDirPath(io, dir);
    }

    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = output_path,
        .data = response_text,
    });

    printer.filepath(file_path);
}

/// Fetch static params from server via x-zx-static-data header
/// Returns expanded paths (e.g., "/blog/hello", "/blog/world")
fn fetchStaticParams(io: std.Io, allocator: std.mem.Allocator, host: []const u8, port: u16, route_path: []const u8) !StaticParamsResult {
    var client = std.http.Client{
        .allocator = allocator,
        .io = io,
    };
    defer client.deinit();

    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();

    const effective_host = if (std.mem.eql(u8, host, "0.0.0.0")) "127.0.0.1" else host;
    const url = try std.fmt.allocPrint(allocator, "http://{s}:{d}{s}", .{ effective_host, port, route_path });
    defer allocator.free(url);

    var extra_headers: [1]std.http.Header = .{.{ .name = "x-zx-static-data", .value = "true" }};

    log.debug("Fetching static params url={s}", .{url});

    const result = try client.fetch(.{
        .method = .GET,
        .location = .{ .url = url },
        .extra_headers = &extra_headers,
        .response_writer = &aw.writer,
    });

    const response = aw.written();
    log.debug("Static params response for {s}: status={} body_len={d}", .{ route_path, result.status, response.len });

    if (result.status != .ok) return .{ .items = &.{}, .allocator = null };

    if (response.len == 0 or std.mem.eql(u8, response, ".{}")) return .{ .items = &.{}, .allocator = null };

    const response_z = try allocator.dupeSentinel(u8, response, 0);
    defer allocator.free(response_z);

    const parsed = std.zon.parse.fromSliceAlloc([]const []const options_mod.StaticParam, allocator, response_z, null, .{}) catch |err| {
        log.warn("Failed to parse static params ZON: {any}", .{err});
        return .{ .items = &.{}, .allocator = null };
    };
    defer std.zon.parse.free(allocator, parsed);

    // Expand dynamic paths
    var expanded = std.array_list.Managed([]const u8).init(allocator);
    errdefer {
        for (expanded.items) |path| allocator.free(path);
        expanded.deinit();
    }

    for (parsed) |param_set| {
        const expanded_path = expandDynamicPath(allocator, route_path, param_set) catch continue;
        expanded.append(expanded_path) catch {
            allocator.free(expanded_path);
            continue;
        };
    }

    if (expanded.items.len == 0) {
        expanded.deinit();
        return .{ .items = &.{}, .allocator = null };
    }

    const items = try expanded.toOwnedSlice();
    return .{ .items = items, .allocator = allocator };
}

/// Replace `:param` and `*` dynamic segments in a route path with actual values.
fn expandDynamicPath(allocator: std.mem.Allocator, route_path: []const u8, params: []const options_mod.StaticParam) ![]const u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();

    var i: usize = 0;
    var first = true;
    while (i <= route_path.len) {
        const end = if (i < route_path.len)
            std.mem.indexOfScalarPos(u8, route_path, i, '/') orelse route_path.len
        else
            route_path.len;
        const seg = route_path[i..end];

        if (!first) try out.append('/');
        first = false;

        const replacement: ?[]const u8 = if (seg.len > 0 and seg[0] == ':')
            findStaticParamValue(params, seg[1..])
        else if (seg.len == 1 and seg[0] == '*')
            findStaticParamValue(params, "*")
        else
            null;

        if (replacement) |value| {
            try out.appendSlice(value);
        } else {
            try out.appendSlice(seg);
        }

        if (end == route_path.len) break;
        i = end + 1;
    }

    return out.toOwnedSlice();
}

fn findStaticParamValue(params: []const options_mod.StaticParam, key: []const u8) ?[]const u8 {
    for (params) |param| {
        if (std.mem.eql(u8, param.key, key)) return param.value;
    }
    return null;
}

const std = @import("std");
const zli = @import("zli");
const cli_options = @import("cli_options");
const util = @import("shared/util.zig");
const flag = @import("shared/flag.zig");
const AppContext = @import("shared/context.zig").AppContext;
const Server = @import("../runtime/server/Server.zig");
const options_mod = @import("../runtime/core/options.zig");
const DevServer = @import("dev/DevServer.zig");
const tui = @import("../tui/main.zig");
const ManifestApp = @import("../build/Manifest.zig").App;
const log = std.log.scoped(.cli);
const builtin = @import("builtin");
