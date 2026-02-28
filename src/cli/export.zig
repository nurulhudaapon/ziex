pub fn register(writer: *std.Io.Writer, reader: *std.Io.Reader, allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(writer, reader, allocator, .{
        .name = "export",
        .description = "Export the site to a static HTML directory",
    }, @"export");

    try cmd.addFlag(outdir_flag);
    try cmd.addFlag(flag.binpath_flag);

    return cmd;
}

const outdir_flag = zli.Flag{
    .name = "outdir",
    .shortcut = "o",
    .description = "Output directory",
    .type = .String,
    .default_value = .{ .String = "dist" },
};

fn @"export"(ctx: zli.CommandContext) !void {
    const outdir = ctx.flag("outdir", []const u8);
    const binpath = ctx.flag("binpath", []const u8);

    var app_meta = util.findprogram(ctx.allocator, binpath) catch |err| {
        if (err == error.FileNotFound) {
            try ctx.writer.print("Run \x1b[34mzig build\x1b[0m to build the ZX executable first!\n", .{});
            return;
        }
        try ctx.writer.print("Error finding ZX executable! {any}\n", .{err});
        return;
    };
    defer std.zon.parse.free(ctx.allocator, app_meta);

    const port = app_meta.config.server.port orelse 3000;
    const appoutdir = app_meta.rootdir orelse "site/.zx";
    const host = app_meta.config.server.address orelse "0.0.0.0";

    var app_child = std.process.Child.init(&.{ app_meta.binpath.?, "--cli-command", "export" }, ctx.allocator);
    app_child.stdout_behavior = .Ignore;
    app_child.stderr_behavior = .Ignore;
    try app_child.spawn();
    defer _ = app_child.kill() catch {};
    errdefer _ = app_child.kill() catch {};

    var printer = tui.Printer.init(ctx.allocator, .{ .file_path_mode = .flat, .file_tree_max_depth = 1 });
    defer printer.deinit();

    printer.header("{s} Building static ZX site!", .{tui.Printer.emoji("○")});
    printer.info("{s}", .{outdir});
    // delete the outdir if it exists
    // std.fs.cwd().deleteTree(outdir) catch |err| switch (err) {
    //     else => {},
    // };

    var aw = std.Io.Writer.Allocating.init(ctx.allocator);
    defer aw.deinit();
    try app_meta.serialize(&aw.writer);
    log.debug("Building static ZX site! {s}", .{aw.written()});

    log.debug("Port: {d}, Outdir: {s}", .{ port, appoutdir });

    log.debug("Processing routes! {d}", .{app_meta.routes.len});

    process_block: while (true) {
        for (app_meta.routes) |route| {
            log.debug("Processing route! {s}", .{route.path});

            if (route.is_dynamic) {
                const static_params = fetchStaticParams(ctx.allocator, host, port, route.path) catch |err| {
                    if (err == error.ConnectionRefused) {
                        continue :process_block;
                    }
                    log.warn("Failed to fetch static params for {s}: {any}", .{ route.path, err });
                    continue;
                };
                defer static_params.deinit();

                if (static_params.items.len > 0) {
                    for (static_params.items) |expanded_path| {
                        const expanded_route = zx.App.SerilizableAppMeta.Route{
                            .path = expanded_path,
                            .method = route.method,
                            .has_notfound = route.has_notfound,
                            .is_dynamic = false,
                        };
                        processRoute(ctx.allocator, host, port, expanded_route, outdir, &printer, .page) catch |err| {
                            if (err == error.ConnectionRefused) {
                                continue :process_block;
                            }
                        };
                    }
                } else {
                    log.debug("No static params for dynamic route: {s}", .{route.path});
                }
            } else {
                processRoute(ctx.allocator, host, port, route, outdir, &printer, .page) catch |err| {
                    if (err == error.ConnectionRefused) {
                        continue :process_block;
                    }
                };
            }

            // Also export 404.html for routes that have notfound handler
            if (route.has_notfound) {
                processRoute(ctx.allocator, host, port, route, outdir, &printer, .notfound) catch |err| {
                    if (err == error.ConnectionRefused) {
                        continue :process_block;
                    }
                };
            }
        }
        break;
    }

    log.debug("Copying public directory! {s}", .{appoutdir});

    util.copydirs(ctx.allocator, appoutdir, &.{ "public", "assets" }, outdir, true, &printer) catch |err| {
        std.log.err("Failed to copy public directory: {any}", .{err});
        // return err;
    };

    // Delete {outdir}/.well-known/_zx if it exists
    const assets_zx_path = try std.fs.path.join(ctx.allocator, &.{ outdir, ".well-known", "_zx" });
    defer ctx.allocator.free(assets_zx_path);
    std.fs.cwd().deleteTree(assets_zx_path) catch |err| switch (err) {
        else => {},
    };

    // printer.footer("", .{});
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
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    route: zx.App.SerilizableAppMeta.Route,
    outdir: []const u8,
    printer: *tui.Printer,
    export_type: ExportType,
) !void {
    // Fetch the route's HTML content
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();

    const effective_host = if (std.mem.eql(u8, host, "0.0.0.0")) "127.0.0.1" else host;
    const url = try std.fmt.allocPrint(allocator, "http://{s}:{d}{s}", .{ effective_host, port, route.path });
    defer allocator.free(url);

    var extra_headers: [1]std.http.Header = .{.{ .name = "x-zx-export-notfound", .value = "true" }};

    _ = try client.fetch(.{
        .method = .GET,
        .location = .{ .url = url },
        .extra_headers = if (export_type == .notfound) &extra_headers else &.{},
        .response_writer = &aw.writer,
    });

    const response_text = aw.written();

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
        try std.fs.cwd().makePath(dir);
    }

    try std.fs.cwd().writeFile(.{
        .sub_path = output_path,
        .data = response_text,
    });

    printer.filepath(file_path);
}

/// Fetch static params from server via x-zx-static-data header
/// Returns expanded paths (e.g., "/blog/hello", "/blog/world")
fn fetchStaticParams(allocator: std.mem.Allocator, host: []const u8, port: u16, route_path: []const u8) !StaticParamsResult {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();

    const effective_host = if (std.mem.eql(u8, host, "0.0.0.0")) "127.0.0.1" else host;
    const url = try std.fmt.allocPrint(allocator, "http://{s}:{d}{s}", .{ effective_host, port, route_path });
    defer allocator.free(url);

    var extra_headers: [1]std.http.Header = .{.{ .name = "x-zx-static-data", .value = "true" }};

    const result = try client.fetch(.{
        .method = .GET,
        .location = .{ .url = url },
        .extra_headers = &extra_headers,
        .response_writer = &aw.writer,
    });

    if (result.status != .ok) return .{ .items = &.{}, .allocator = null };

    const response = aw.written();
    if (response.len == 0 or std.mem.eql(u8, response, ".{}")) return .{ .items = &.{}, .allocator = null };

    const response_z = try allocator.dupeZ(u8, response);
    defer allocator.free(response_z);

    const parsed = std.zon.parse.fromSlice([]const []const zx.PageOptions.StaticParam, allocator, response_z, null, .{}) catch |err| {
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

/// Replace :param placeholders in a route path with actual values
fn expandDynamicPath(allocator: std.mem.Allocator, route_path: []const u8, params: []const zx.PageOptions.StaticParam) ![]const u8 {
    var result = try allocator.dupe(u8, route_path);

    for (params) |param| {
        const placeholder = try std.fmt.allocPrint(allocator, ":{s}", .{param.key});
        defer allocator.free(placeholder);

        if (std.mem.indexOf(u8, result, placeholder)) |start| {
            const new_len = result.len - placeholder.len + param.value.len;
            const new_result = try allocator.alloc(u8, new_len);
            @memcpy(new_result[0..start], result[0..start]);
            @memcpy(new_result[start .. start + param.value.len], param.value);
            @memcpy(new_result[start + param.value.len ..], result[start + placeholder.len ..]);
            allocator.free(result);
            result = new_result;
        }
    }

    return result;
}

const std = @import("std");
const zli = @import("zli");
const util = @import("shared/util.zig");
const flag = @import("shared/flag.zig");
const zx = @import("zx");
const tui = @import("../tui/main.zig");
const log = std.log.scoped(.cli);
