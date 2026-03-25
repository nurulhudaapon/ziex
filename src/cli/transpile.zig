const std = @import("std");
const zli = @import("zli");
const zx = @import("zx");
const log = std.log.scoped(.cli);
const util = @import("shared/util.zig");
const jsutil = @import("shared/js.zig");
const flags = @import("shared/flag.zig");
const base64 = std.base64.standard;

// ============================================================================
// Command Registration
// ============================================================================

const outdir_flag = zli.Flag{
    .name = "outdir",
    .shortcut = "o",
    .description = "Output directory",
    .type = .String,
    .default_value = .{ .String = ".zx" },
};

const copy_only_flag = zli.Flag{
    .name = "copy-only",
    .description = "Copy only the files to the output directory",
    .type = .Bool,
    .default_value = .{ .Bool = false },
};

const map_flag = zli.Flag{
    .name = "map",
    .description = "Generate source map",
    .type = .String,
    .default_value = .{ .String = "none" },
};

const copy_embedded_sources_flag = zli.Flag{
    .name = "copy-embedded-sources",
    .description = "Copy embedded .zx source files to output directory and rewrite paths",
    .type = .Bool,
    .default_value = .{ .Bool = false },
};

const rootdir_flag = zli.Flag{
    .name = "rootdir",
    .description = "Root directory for the generated meta file (e.g., static dir)",
    .type = .String,
    .default_value = .{ .String = "" },
};

const depfile_flag = zli.Flag{
    .name = "dep-file",
    .description = "Write a Make-format dependency file listing all transpiled input files",
    .type = .String,
    .default_value = .{ .String = "" },
};

const cachedir_flag = zli.Flag{
    .name = "cache-dir",
    .description = "Persistent directory for content-hash-keyed transpile cache (survives zig-cache invalidation)",
    .type = .String,
    .default_value = .{ .String = "" },
};

pub fn register(writer: *std.Io.Writer, reader: *std.Io.Reader, allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(writer, reader, allocator, .{
        .name = "transpile",
        .description = "Transpile a .zx file or directory to zig source code.",
    }, transpile);

    try cmd.addFlag(outdir_flag);
    try cmd.addFlag(copy_only_flag);
    try cmd.addFlag(flags.verbose_flag);
    try cmd.addFlag(map_flag);
    try cmd.addFlag(copy_embedded_sources_flag);
    try cmd.addFlag(rootdir_flag);
    try cmd.addFlag(depfile_flag);
    try cmd.addFlag(cachedir_flag);
    try cmd.addPositionalArg(.{
        .name = "path",
        .description = "Path to .zx file or directory",
        .required = true,
    });
    return cmd;
}

fn transpile(ctx: zli.CommandContext) !void {
    const outdir = ctx.flag("outdir", []const u8);

    const copy_only = ctx.flag("copy-only", bool);
    const verbose = ctx.flag("verbose", bool);
    const sourcemap_str = ctx.flag("map", []const u8);
    const copy_embedded_sources = ctx.flag("copy-embedded-sources", bool);
    const rootdir_str = ctx.flag("rootdir", []const u8);
    const rootdir: ?[]const u8 = if (rootdir_str.len > 0) rootdir_str else null;
    const depfile_str = ctx.flag("dep-file", []const u8);
    const dep_file: ?[]const u8 = if (depfile_str.len > 0) depfile_str else null;
    const map: zx.Ast.ParseOptions.MapMode = if (std.mem.eql(u8, sourcemap_str, "inline"))
        .inlined
    else if (std.mem.eql(u8, sourcemap_str, "none"))
        .none
    else if (sourcemap_str.len > 0 and !std.mem.eql(u8, sourcemap_str, "none"))
        .{ .file = sourcemap_str }
    else
        .none;
    const path = ctx.getArg("path") orelse {
        try ctx.writer.print("Missing path arg\n", .{});
        return;
    };

    if (verbose) {
        std.debug.print("Transpiling: {s} -> {s} (copy_only: {any}, verbose: {any})\n", .{ path, outdir, copy_only, verbose });
    }

    // std.debug.print("Copying only the files to the output directory: from {s} to {s} (copy_only: {any})\n", .{ path, outdir, copy_only });
    // We no longer copy assets/public here, as it's now handled by the Zig build system

    if (copy_only) return copyOnly(ctx, path, outdir) catch |err| {
        std.debug.print("Error: Could not copy path '{s} -> {s}': {}\n", .{ path, outdir, err });
        return err;
    };

    // Check if path is a file and outdir is default
    const default_outdir = ".zx";
    const is_default_outdir = std.mem.eql(u8, outdir, default_outdir);

    // Check if path is a file (not a directory)
    const stat = std.fs.cwd().statFile(path) catch |err| switch (err) {
        error.IsDir => {
            // It's a directory, proceed with normal transpileCommand
            try transpileCommand(ctx.allocator, .{
                .path = path,
                .outdir = outdir,
                .verbose = verbose,
                .map = map,
                .copy_embedded_sources = copy_embedded_sources,
                .rootdir = rootdir,
                .dep_file = dep_file,
            });
            return;
        },
        else => {
            std.debug.print("Error: Could not access path '{s}': {}\n", .{ path, err });
            return err;
        },
    };

    // Path is a file
    if (stat.kind == .file) {
        const is_zx = std.mem.endsWith(u8, path, ".zx");

        if (is_zx) {
            // If outdir is default and path is a file, output to stdout
            if (is_default_outdir) {
                // Read the source file
                const source = try std.fs.cwd().readFileAlloc(
                    ctx.allocator,
                    path,
                    std.math.maxInt(usize),
                );
                defer ctx.allocator.free(source);

                const source_z = try ctx.allocator.dupeZ(u8, source);
                defer ctx.allocator.free(source_z);

                // Parse and transpile
                var result = try zx.Ast.parse(ctx.allocator, source_z, .{ .path = path, .map = map });
                defer result.deinit(ctx.allocator);

                // Output to stdout
                try ctx.writer.writeAll(result.zig_source);

                // Handle sourcemap for stdout output
                if (result.sourcemap) |sm| {
                    switch (map) {
                        .none => {},
                        .file => |map_path| {
                            // Write sourcemap to the specified file
                            const sourcemap_json = try sm.toJSON(
                                ctx.allocator,
                                path,
                                path,
                                source,
                                result.zig_source,
                            );
                            defer ctx.allocator.free(sourcemap_json);

                            try std.fs.cwd().writeFile(.{
                                .sub_path = map_path,
                                .data = sourcemap_json,
                            });
                        },
                        .inlined => {
                            // Append inline sourcemap to stdout
                            const sourcemap_json = try sm.toJSON(
                                ctx.allocator,
                                path,
                                path,
                                source,
                                null,
                            );
                            defer ctx.allocator.free(sourcemap_json);

                            const base64_encoded = try base64Encode(ctx.allocator, sourcemap_json);
                            defer ctx.allocator.free(base64_encoded);

                            try ctx.writer.print("\n//# sourceMappingURL=data:application/json;base64,{s}\n", .{base64_encoded});
                        },
                    }
                }
                return;
            }
        }
    }

    // Otherwise, proceed with normal transpileCommand
    try transpileCommand(ctx.allocator, .{
        .path = path,
        .outdir = outdir,
        .verbose = verbose,
        .map = map,
        .copy_embedded_sources = copy_embedded_sources,
        .rootdir = rootdir,
        .dep_file = dep_file,
    });
}

fn base64Encode(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    const encoded_len = base64.Encoder.calcSize(data.len);
    const encoded = try allocator.alloc(u8, encoded_len);
    _ = base64.Encoder.encode(encoded, data);
    return encoded;
}

// ---- Dep File ---- //

fn writeDepFile(allocator: std.mem.Allocator, path: []const u8, target: []const u8, deps: []const []const u8) !void {
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(allocator);
    try buf.appendSlice(allocator, target);
    try buf.appendSlice(allocator, ":");
    for (deps) |dep| {
        try buf.appendSlice(allocator, " ");
        for (dep) |c| {
            if (c == ' ') {
                try buf.appendSlice(allocator, "\\ ");
            } else {
                try buf.append(allocator, c);
            }
        }
    }
    try buf.appendSlice(allocator, "\n");
    const f = try std.fs.cwd().createFile(path, .{});
    defer f.close();
    try f.writeAll(buf.items);
}

// ---- Component Cache (per-file incremental) ---- //

fn writeComponentCache(
    allocator: std.mem.Allocator,
    cache_path: []const u8,
    components: []const ClientComponentSerializable,
) !void {
    const json = try std.json.Stringify.valueAlloc(allocator, components, .{});
    defer allocator.free(json);
    try std.fs.cwd().writeFile(.{ .sub_path = cache_path, .data = json });
}

fn readComponentCache(
    allocator: std.mem.Allocator,
    cache_path: []const u8,
    global_components: *std.array_list.Managed(ClientComponentSerializable),
) !void {
    const json = try std.fs.cwd().readFileAlloc(allocator, cache_path, 4 * 1024 * 1024);
    defer allocator.free(json);
    const parsed = try std.json.parseFromSlice(
        []const ClientComponentSerializable,
        allocator,
        json,
        .{},
    );
    defer parsed.deinit();
    for (parsed.value) |component| {
        try global_components.append(.{
            .type = component.type,
            .id = try allocator.dupe(u8, component.id),
            .name = try allocator.dupe(u8, component.name),
            .path = try allocator.dupe(u8, component.path),
            .import = try allocator.dupe(u8, component.import),
            .route = try allocator.dupe(u8, component.route),
        });
    }
}

fn copyOnly(ctx: zli.CommandContext, source_path: []const u8, dest_dir: []const u8) !void {
    const stat = std.fs.cwd().statFile(source_path) catch |err| switch (err) {
        error.IsDir => return try copyDirectory(ctx.allocator, source_path, dest_dir),
        else => return err,
    };
    if (stat.kind == .directory) try copyDirectory(ctx.allocator, source_path, dest_dir);
    if (stat.kind == .file) try copyFileToDir(ctx.allocator, source_path, dest_dir);
}

// ---- Path Utilities ---- //

/// Extract route from source path based on filesystem routing
/// If the file is in a pages directory, returns the route (e.g., "/about", "/")
/// Otherwise returns empty string
fn extractRouteFromPath(allocator: std.mem.Allocator, source_path: []const u8) ![]const u8 {
    const sep = std.fs.path.sep_str;
    const pages_sep = "pages" ++ sep;

    // Check if source_path contains "pages" directory
    if (std.mem.indexOf(u8, source_path, pages_sep)) |pages_index| {
        // Get the path after "pages/"
        const after_pages = source_path[pages_index + pages_sep.len ..];

        // Find the directory containing the file (remove filename)
        const dir_path = std.fs.path.dirname(after_pages) orelse "";

        // Convert directory path to route
        if (dir_path.len == 0) {
            return try allocator.dupe(u8, "/");
        }

        // Normalize the route: convert [id] to :id and path separators to /
        var normalized_route = std.array_list.Managed(u8).init(allocator);
        defer normalized_route.deinit();
        try normalized_route.append('/');

        for (dir_path) |c| {
            if (c == std.fs.path.sep) {
                try normalized_route.append('/');
            } else if (c == '[') {
                try normalized_route.append(':');
            } else if (c != ']') {
                try normalized_route.append(c);
            }
        }

        return try normalized_route.toOwnedSlice();
    }

    // Not in pages directory, return empty string
    return try allocator.dupe(u8, "");
}

/// Get the package root directory (where node_modules is located)
/// This function finds package.json and returns its directory
fn getPackageRootDir(allocator: std.mem.Allocator) ![]const u8 {
    const package_json_parsed = try jsutil.PackageJson.parse(allocator);
    errdefer package_json_parsed.deinit();

    // Extract pkg_path before deinit since it's manually allocated
    const pkg_path = package_json_parsed.value.pkg_path orelse {
        package_json_parsed.deinit();
        return error.PkgPathNotFound;
    };

    const pkg_rootdir = std.fs.path.dirname(pkg_path) orelse {
        allocator.free(pkg_path);
        package_json_parsed.deinit();
        // When package.json is in root, return empty string (current directory)
        return try allocator.dupe(u8, "");
    };

    const result = try allocator.dupe(u8, pkg_rootdir);

    // Free pkg_path manually since it's not part of the JSON structure
    // and won't be freed by package_json_parsed.deinit()
    allocator.free(pkg_path);
    package_json_parsed.deinit();

    return result;
}

fn getBasename(path: []const u8) []const u8 {
    const sep = std.fs.path.sep;
    if (std.mem.lastIndexOfScalar(u8, path, sep)) |last_sep| {
        if (last_sep + 1 < path.len) {
            return path[last_sep + 1 ..];
        }
    }
    return path;
}

/// Escapes backslashes in a path string for use in Zig string literals.
/// On Windows, backslashes need to be escaped as \\ in string literals.
fn escapePathForZigString(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    errdefer result.deinit();
    const writer = result.writer();

    for (path) |byte| {
        if (byte == '\\') {
            // Escape backslash for Zig string literal
            try writer.writeAll("\\\\");
        } else {
            try writer.writeByte(byte);
        }
    }

    return result.toOwnedSlice();
}

/// Resolve a relative path against a base directory
fn resolvePath(allocator: std.mem.Allocator, base_dir: []const u8, relative_path: []const u8) ![]const u8 {
    if (std.fs.path.isAbsolute(relative_path)) {
        return try allocator.dupe(u8, relative_path);
    }

    var base = base_dir;
    const sep = std.fs.path.sep_str;
    if (std.mem.endsWith(u8, base_dir, sep)) {
        base = base_dir[0 .. base_dir.len - sep.len];
    }

    const joined = try std.fs.path.join(allocator, &.{ base, relative_path });
    defer allocator.free(joined);

    return try std.fs.path.resolve(allocator, &.{joined});
}

/// Calculate relative path from base to target
fn relativePath(allocator: std.mem.Allocator, base: []const u8, target: []const u8) ![]const u8 {
    const sep = std.fs.path.sep_str;

    var base_normalized = base;
    var target_normalized = target;
    if (std.mem.endsWith(u8, base, sep)) {
        base_normalized = base[0 .. base.len - sep.len];
    }
    if (std.mem.endsWith(u8, target, sep)) {
        target_normalized = target[0 .. target.len - sep.len];
    }

    var base_parts = std.ArrayList([]const u8){};
    defer base_parts.deinit(allocator);
    var target_parts = std.ArrayList([]const u8){};
    defer target_parts.deinit(allocator);

    var base_iter = std.mem.splitScalar(u8, base_normalized, std.fs.path.sep);
    while (base_iter.next()) |part| {
        if (part.len > 0) {
            try base_parts.append(allocator, part);
        }
    }

    var target_iter = std.mem.splitScalar(u8, target_normalized, std.fs.path.sep);
    while (target_iter.next()) |part| {
        if (part.len > 0) {
            try target_parts.append(allocator, part);
        }
    }

    var common_len: usize = 0;
    const min_len = @min(base_parts.items.len, target_parts.items.len);
    while (common_len < min_len and std.mem.eql(u8, base_parts.items[common_len], target_parts.items[common_len])) {
        common_len += 1;
    }

    var result = std.ArrayList(u8){};
    defer result.deinit(allocator);

    var i = common_len;
    while (i < base_parts.items.len) : (i += 1) {
        if (result.items.len > 0) {
            try result.appendSlice(allocator, sep);
        }
        try result.appendSlice(allocator, "..");
    }

    i = common_len;
    while (i < target_parts.items.len) : (i += 1) {
        if (result.items.len > 0) {
            try result.appendSlice(allocator, sep);
        }
        try result.appendSlice(allocator, target_parts.items[i]);
    }

    if (result.items.len == 0) {
        return try allocator.dupe(u8, ".");
    }

    return try result.toOwnedSlice(allocator);
}

/// Check if output_dir is a subdirectory of dir_path and return the relative path if so
fn getOutputDirRelativePath(allocator: std.mem.Allocator, dir_path: []const u8, output_dir: []const u8) !?[]const u8 {
    const sep = std.fs.path.sep_str;

    var normalized_dir = dir_path;
    if (std.mem.endsWith(u8, dir_path, sep)) {
        normalized_dir = dir_path[0 .. dir_path.len - sep.len];
    }

    var normalized_output = output_dir;
    if (std.mem.endsWith(u8, output_dir, sep)) {
        normalized_output = output_dir[0 .. output_dir.len - sep.len];
    }

    if (!std.mem.startsWith(u8, normalized_output, normalized_dir)) {
        return null;
    }

    if (std.mem.eql(u8, normalized_dir, normalized_output)) {
        return null;
    }

    const remaining = normalized_output[normalized_dir.len..];
    if (remaining.len == 0) {
        return null;
    }

    if (!std.mem.startsWith(u8, remaining, sep)) {
        return null;
    }

    const relative_path = remaining[sep.len..];
    if (relative_path.len == 0) {
        return null;
    }

    return try allocator.dupe(u8, relative_path);
}

// ---- File Operations ---- //
fn copyFileToDir(
    allocator: std.mem.Allocator,
    source_file: []const u8,
    dest_dir: []const u8,
) !void {
    const dest_file = try std.fs.path.join(allocator, &.{ dest_dir, std.fs.path.basename(source_file) });
    defer allocator.free(dest_file);
    std.fs.cwd().makePath(dest_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    try std.fs.cwd().copyFile(source_file, std.fs.cwd(), dest_file, .{});
}

/// Copy a directory recursively from source to destination
fn copyDirectory(
    allocator: std.mem.Allocator,
    source_dir: []const u8,
    dest_dir: []const u8,
) !void {
    var source = try std.fs.cwd().openDir(source_dir, .{ .iterate = true });
    defer source.close();

    std.fs.cwd().makePath(dest_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    var dest = try std.fs.cwd().openDir(dest_dir, .{});
    defer dest.close();

    var walker = try source.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        const src_path = try std.fs.path.join(allocator, &.{ source_dir, entry.path });
        defer allocator.free(src_path);

        const dst_path = try std.fs.path.join(allocator, &.{ dest_dir, entry.path });
        defer allocator.free(dst_path);

        switch (entry.kind) {
            .file => {
                if (std.fs.path.dirname(dst_path)) |parent| {
                    std.fs.cwd().makePath(parent) catch |err| switch (err) {
                        error.PathAlreadyExists => {},
                        else => return err,
                    };
                }
                try std.fs.cwd().copyFile(src_path, std.fs.cwd(), dst_path, .{});
            },
            .directory => {
                std.fs.cwd().makePath(dst_path) catch |err| switch (err) {
                    error.PathAlreadyExists => {},
                    else => return err,
                };
            },
            else => continue,
        }
    }
}

// ---- Client Component Handling ---- //
const ClientComponentSerializable = struct { type: zx.BuiltinAttribute.Rendering, id: []const u8, name: []const u8, path: []const u8, import: []const u8, route: []const u8 };
fn genClientComponents(allocator: std.mem.Allocator, components: []const ClientComponentSerializable, output_dir: []const u8, verbose: bool) !void {
    _ = verbose;
    // Generate Zig array literal contents (without outer array declaration)
    var aw = std.io.Writer.Allocating.init(allocator);
    defer aw.deinit();

    std.zon.stringify.serialize(components, .{ .whitespace = true }, &aw.writer) catch @panic("OOM");

    var zon_str = try allocator.dupe(u8, aw.written());
    defer allocator.free(zon_str);

    // Replace all instances of "@ and @" with empty string (similar to JSON handling)
    const placeHolder_start = "\"@";
    const placeHolder_end = "@\"";

    while (std.mem.indexOf(u8, zon_str, placeHolder_start)) |index| {
        const old_zon_str = zon_str;
        const before = zon_str[0..index];
        const after = zon_str[index + placeHolder_start.len ..];
        zon_str = try std.mem.concat(allocator, u8, &.{ before, "", after });
        allocator.free(old_zon_str);
    }
    while (std.mem.indexOf(u8, zon_str, placeHolder_end)) |index| {
        const old_zon_str = zon_str;
        const before = zon_str[0..index];
        const after = zon_str[index + placeHolder_end.len ..];
        zon_str = try std.mem.concat(allocator, u8, &.{ before, "", after });
        allocator.free(old_zon_str);
    }

    // Replace @@@ with @ (for @import, @intCast, etc.)
    while (std.mem.indexOf(u8, zon_str, "@@@")) |index| {
        const old_zon_str = zon_str;
        const before = zon_str[0..index];
        const after = zon_str[index + 3 ..]; // Skip "@@@"
        zon_str = try std.mem.concat(allocator, u8, &.{ before, "@", after });
        allocator.free(old_zon_str);
    }

    // Replace @@ placeholders with double quotes (for quotes inside @import())
    while (std.mem.indexOf(u8, zon_str, "@@")) |index| {
        const old_zon_str = zon_str;
        const before = zon_str[0..index];
        const after = zon_str[index + 2 ..]; // Skip "@@"
        zon_str = try std.mem.concat(allocator, u8, &.{ before, "\"", after });
        allocator.free(old_zon_str);
    }

    // Remove any trailing standalone @ that might be left (from the end marker)
    if (zon_str.len > 0 and zon_str[zon_str.len - 1] == '@') {
        const old_zon_str = zon_str;
        zon_str = try allocator.dupe(u8, zon_str[0 .. zon_str.len - 1]);
        allocator.free(old_zon_str);
    }

    const cmps_client = @embedFile("./transpile/template/components.zig");
    const placeholder = "    // PLACEHOLDER_ZX_COMPONENTS\n";
    const placeholder_index = std.mem.indexOf(u8, cmps_client, placeholder) orelse {
        @panic("Placeholder PLACEHOLDER_ZX_COMPONENTS not found in components.zig");
    };

    const before = cmps_client[0..placeholder_index];
    const after = cmps_client[placeholder_index + placeholder.len ..];

    const cmps_client_z = try std.mem.concat(allocator, u8, &.{ before, zon_str[2..(zon_str.len - 1)], after });
    defer allocator.free(cmps_client_z);

    const cmps_client_path = try std.fs.path.join(allocator, &.{ output_dir, "components.zig" });
    defer allocator.free(cmps_client_path);

    try std.fs.cwd().writeFile(.{
        .sub_path = cmps_client_path,
        .data = cmps_client_z,
    });
}

fn genReactComponents(allocator: std.mem.Allocator, components: []const ClientComponentSerializable, output_dir: []const u8, verbose: bool) !void {
    if (components.len == 0) return;

    var json_str = std.json.Stringify.valueAlloc(allocator, components, .{
        .whitespace = .indent_2,
    }) catch @panic("OOM");
    errdefer allocator.free(json_str);

    // Replace all instances of "@ and @" with empty string
    const placeHolder_start = "\"@";
    const placeHolder_end = "@\"";

    while (std.mem.indexOf(u8, json_str, placeHolder_start)) |index| {
        const old_json_str = json_str;
        const before = json_str[0..index];
        const after = json_str[index + placeHolder_start.len ..];
        json_str = try std.mem.concat(allocator, u8, &.{ before, "", after });
        allocator.free(old_json_str);
    }
    while (std.mem.indexOf(u8, json_str, placeHolder_end)) |index| {
        const old_json_str = json_str;
        const before = json_str[0..index];
        const after = json_str[index + placeHolder_end.len ..];
        json_str = try std.mem.concat(allocator, u8, &.{ before, "", after });
        allocator.free(old_json_str);
    }
    defer allocator.free(json_str);

    const main_csr_react = @embedFile("./transpile/template/components.ts");
    const placeholder = "`{[ZX_COMPONENTS]s}`";
    const placeholder_index = std.mem.indexOf(u8, main_csr_react, placeholder) orelse {
        @panic("Placeholder {ZX_COMPONENTS} not found in main_csr_react.tsx");
    };

    const before = main_csr_react[0..placeholder_index];
    const after = main_csr_react[placeholder_index + placeholder.len ..];
    const registry_exp = "export const registry = Object.fromEntries(components.map(c => [c.name, c.import]));";

    const main_csr_react_z = try std.mem.concat(allocator, u8, &.{ before, json_str, after, registry_exp });
    defer allocator.free(main_csr_react_z);

    _ = output_dir;
    if (verbose) {
        log.debug("node_modules path: {s}", .{"node_modules"});
        log.debug("ziex path: {s}", .{"ziex"});
        log.debug("components.ts path: {s}", .{"components.ts"});
    }

    const pkg_rootdir = try getPackageRootDir(allocator);
    defer allocator.free(pkg_rootdir);

    const ziex_dir = try std.fs.path.join(allocator, &.{ pkg_rootdir, "node_modules", "@ziex/components" });
    defer allocator.free(ziex_dir);
    std.fs.cwd().makePath(ziex_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const main_csr_react_path = try std.fs.path.join(allocator, &.{ ziex_dir, "index.ts" });
    defer allocator.free(main_csr_react_path);

    try std.fs.cwd().writeFile(.{
        .sub_path = main_csr_react_path,
        .data = main_csr_react_z,
    });
}

// --- Route and Meta Generation --- //
const Route = struct {
    path: []const u8,
    page_import: ?[]const u8 = null,
    layout_import: ?[]const u8 = null,
    notfound_import: ?[]const u8 = null,
    error_import: ?[]const u8 = null,
    route_import: ?[]const u8 = null, // API route import
    proxy_import: ?[]const u8 = null, // Proxy middleware import (cascades at runtime like layouts)

    fn deinit(self: *Route, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        if (self.page_import) |import| {
            allocator.free(import);
        }
        if (self.layout_import) |import| {
            allocator.free(import);
        }
        if (self.notfound_import) |import| {
            allocator.free(import);
        }
        if (self.error_import) |import| {
            allocator.free(import);
        }
        if (self.route_import) |import| {
            allocator.free(import);
        }
        if (self.proxy_import) |import| {
            allocator.free(import);
        }
    }
};

fn genRoutes(allocator: std.mem.Allocator, output_dir: []const u8, rootdir: ?[]const u8, verbose: bool) !void {
    var routes = std.array_list.Managed(Route).init(allocator);
    defer {
        for (routes.items) |*route| {
            route.deinit(allocator);
        }
        routes.deinit();
    }

    // Scan pages directory
    const pages_dir = try std.fs.path.join(allocator, &.{ output_dir, "pages" });
    defer allocator.free(pages_dir);

    const has_pages = blk: {
        std.fs.cwd().access(pages_dir, .{}) catch break :blk false;
        break :blk true;
    };

    if (has_pages) {
        if (verbose) std.debug.print("Scanning pages directory: {s}\n", .{pages_dir});
        const pages_import_prefix = try std.mem.concat(allocator, u8, &.{"pages"});
        defer allocator.free(pages_import_prefix);

        var layout_stack = std.array_list.Managed([]const u8).init(allocator);
        defer {
            for (layout_stack.items) |layout| {
                allocator.free(layout);
            }
            layout_stack.deinit();
        }

        try scanPagesRecursive(allocator, pages_dir, "", &layout_stack, pages_import_prefix, &routes);
    }

    // Scan routes directory for API routes
    const routes_dir = try std.fs.path.join(allocator, &.{ output_dir, "routes" });
    defer allocator.free(routes_dir);

    const has_routes = blk: {
        std.fs.cwd().access(routes_dir, .{}) catch break :blk false;
        break :blk true;
    };

    if (has_routes) {
        if (verbose) std.debug.print("Scanning routes directory: {s}\n", .{routes_dir});
        const routes_import_prefix = try std.mem.concat(allocator, u8, &.{"routes"});
        defer allocator.free(routes_import_prefix);

        try scanRoutesRecursive(allocator, routes_dir, "", routes_import_prefix, &routes);
    }

    if (!has_pages and !has_routes) {
        if (verbose) std.debug.print("No pages or routes directory found, skipping meta.zig generation\n", .{});
        return error.NoPagesOrRoutes;
    }

    var content = std.array_list.Managed(u8).init(allocator);
    defer content.deinit();
    const writer = content.writer();

    try writer.writeAll("pub const routes = [_]zx.server.ServerMeta.Route{\n");
    for (routes.items) |route| {
        try writeRoute(writer, route);
    }
    try writer.writeAll("};\n\n");

    // Use rootdir if provided, otherwise fall back to output_dir
    const meta_rootdir = rootdir orelse output_dir;

    // Convert to relative path using std.fs.path.relative and escape for Zig string literal
    var path_to_use: []const u8 = meta_rootdir;
    var path_allocated = false;
    if (std.fs.cwd().realpathAlloc(allocator, ".")) |cwd| {
        defer allocator.free(cwd);
        if (std.fs.path.relative(allocator, cwd, meta_rootdir)) |relative| {
            path_to_use = relative;
            path_allocated = true;
        } else |_| {}
    } else |_| {}
    defer if (path_allocated) allocator.free(path_to_use);

    const escaped_path = try escapePathForZigString(allocator, path_to_use);
    defer allocator.free(escaped_path);

    try writer.writeAll("pub const meta = zx.server.ServerMeta{\n");
    try writer.writeAll("    .routes = &routes,\n");
    try writer.print("    .rootdir = \"{s}\",\n", .{escaped_path});
    try writer.writeAll("};\n\n");
    try writer.writeAll("const zx = @import(\"zx\");\n");
    // Re-export components from components.zig (same directory, same module tree)
    try writer.writeAll("pub const components = @import(\"components.zig\");\n\n");
    // Helper function for getting options from a module with inferred return type
    try writer.writeAll("fn getOptions(comptime T: type, comptime R: type) ?R {\n");
    try writer.writeAll("    return if (@hasDecl(T, \"options\")) T.options else null;\n");
    try writer.writeAll("}\n");

    const meta_path = try std.fs.path.join(allocator, &.{ output_dir, "meta.zig" });
    defer allocator.free(meta_path);

    const content_z = try allocator.dupeZ(u8, content.items);
    defer allocator.free(content_z);
    var ast = try std.zig.Ast.parse(allocator, content_z, .zig);
    defer ast.deinit(allocator);

    if (ast.errors.len > 0) {
        return error.ParseError;
    }

    const rendered_zig_source = try ast.renderAlloc(allocator);
    defer allocator.free(rendered_zig_source);

    try std.fs.cwd().writeFile(.{
        .sub_path = meta_path,
        .data = rendered_zig_source,
    });

    if (verbose) std.debug.print("Generated meta.zig at: {s}\n", .{meta_path});
}

fn writeRoute(writer: anytype, route: Route) !void {
    const indent = "    ";

    try writer.print("{s}.{{\n", .{indent});
    try writer.print("{s}    .path = \"{s}\",\n", .{ indent, route.path });

    // Page (optional for API-only routes)
    if (route.page_import) |page| {
        try writer.print("{s}    .page = zx.server.ServerMeta.page(@import(\"{s}\")),\n", .{ indent, page });
    }

    if (route.layout_import) |layout| {
        try writer.print("{s}    .layout = zx.server.ServerMeta.layout(@import(\"{s}\")),\n", .{ indent, layout });
    }

    if (route.notfound_import) |notfound| {
        try writer.print("{s}    .notfound = @import(\"{s}\").NotFound,\n", .{ indent, notfound });
    }

    if (route.error_import) |err_import| {
        try writer.print("{s}    .@\"error\" = @import(\"{s}\").Error,\n", .{ indent, err_import });
    }

    // Page options (only if page exists)
    if (route.page_import) |page| {
        try writer.print("{s}    .page_opts = getOptions(@import(\"{s}\"), zx.PageOptions),\n", .{ indent, page });
    }

    // Layout options (only if layout exists)
    if (route.layout_import) |layout| {
        try writer.print("{s}    .layout_opts = getOptions(@import(\"{s}\"), zx.LayoutOptions),\n", .{ indent, layout });
    }

    // Notfound options (only if notfound exists)
    if (route.notfound_import) |notfound| {
        try writer.print("{s}    .notfound_opts = getOptions(@import(\"{s}\"), zx.NotFoundOptions),\n", .{ indent, notfound });
    }

    // Error options (only if error exists)
    if (route.error_import) |err_import| {
        try writer.print("{s}    .error_opts = getOptions(@import(\"{s}\"), zx.ErrorOptions),\n", .{ indent, err_import });
    }

    // API route handlers (built via route)
    if (route.route_import) |route_import| {
        // Pass page module for method conflict validation when co-located
        if (route.page_import) |page_import| {
            try writer.print("{s}    .route = zx.server.ServerMeta.route(@import(\"{s}\"), @import(\"{s}\")),\n", .{ indent, route_import, page_import });
        } else {
            try writer.print("{s}    .route = zx.server.ServerMeta.route(@import(\"{s}\"), null),\n", .{ indent, route_import });
        }
        try writer.print("{s}    .route_opts = getOptions(@import(\"{s}\"), zx.RouteOptions),\n", .{ indent, route_import });
    }

    // Proxy middleware (Proxy() cascades at runtime like layouts, PageProxy/RouteProxy don't cascade)
    if (route.proxy_import) |proxy_import| {
        try writer.print("{s}    .proxy = zx.server.ServerMeta.proxy(@import(\"{s}\")),\n", .{ indent, proxy_import });
        try writer.print("{s}    .page_proxy = zx.server.ServerMeta.pageProxy(@import(\"{s}\")),\n", .{ indent, proxy_import });
        try writer.print("{s}    .route_proxy = zx.server.ServerMeta.routeProxy(@import(\"{s}\")),\n", .{ indent, proxy_import });
    }

    try writer.print("{s}}},\n", .{indent});
}

fn scanPagesRecursive(
    allocator: std.mem.Allocator,
    current_dir: []const u8,
    current_path: []const u8,
    layout_stack: *std.array_list.Managed([]const u8),
    import_prefix: []const u8,
    routes: *std.array_list.Managed(Route),
) !void {
    const page_path = try std.fs.path.join(allocator, &.{ current_dir, "page.zig" });
    defer allocator.free(page_path);

    const layout_path = try std.fs.path.join(allocator, &.{ current_dir, "layout.zig" });
    defer allocator.free(layout_path);

    const notfound_path = try std.fs.path.join(allocator, &.{ current_dir, "notfound.zig" });
    defer allocator.free(notfound_path);

    const error_path = try std.fs.path.join(allocator, &.{ current_dir, "error.zig" });
    defer allocator.free(error_path);

    const route_file_path = try std.fs.path.join(allocator, &.{ current_dir, "route.zig" });
    defer allocator.free(route_file_path);

    const proxy_file_path = try std.fs.path.join(allocator, &.{ current_dir, "proxy.zig" });
    defer allocator.free(proxy_file_path);

    const has_page = blk: {
        std.fs.cwd().access(page_path, .{}) catch break :blk false;
        break :blk true;
    };

    const has_layout = blk: {
        std.fs.cwd().access(layout_path, .{}) catch break :blk false;
        break :blk true;
    };

    const has_notfound = blk: {
        std.fs.cwd().access(notfound_path, .{}) catch break :blk false;
        break :blk true;
    };

    const has_error = blk: {
        std.fs.cwd().access(error_path, .{}) catch break :blk false;
        break :blk true;
    };

    const has_route = blk: {
        std.fs.cwd().access(route_file_path, .{}) catch break :blk false;
        break :blk true;
    };

    const has_proxy = blk: {
        std.fs.cwd().access(proxy_file_path, .{}) catch break :blk false;
        break :blk true;
    };

    var current_layout_import: ?[]const u8 = null;
    if (has_layout) {
        current_layout_import = try std.mem.concat(allocator, u8, &.{ import_prefix, "/layout.zig" });
        try layout_stack.append(current_layout_import.?);
    }

    if (has_page or has_route or has_proxy) {
        const page_import = if (has_page)
            try std.mem.concat(allocator, u8, &.{ import_prefix, "/page.zig" })
        else
            null;

        // Co-located route.zig in pages directory
        const route_import = if (has_route)
            try std.mem.concat(allocator, u8, &.{ import_prefix, "/route.zig" })
        else
            null;

        // Proxy middleware (cascading handled at runtime like layouts)
        const proxy_import = if (has_proxy)
            try std.mem.concat(allocator, u8, &.{ import_prefix, "/proxy.zig" })
        else
            null;

        // Only set layout if the current directory has a layout file
        const layout_import = if (has_layout)
            try std.mem.concat(allocator, u8, &.{ import_prefix, "/layout.zig" })
        else
            null;

        // Only set notfound if the current directory has a notfound file
        const notfound_import = if (has_notfound)
            try std.mem.concat(allocator, u8, &.{ import_prefix, "/notfound.zig" })
        else
            null;

        // Only set error if the current directory has an error file
        const error_import = if (has_error)
            try std.mem.concat(allocator, u8, &.{ import_prefix, "/error.zig" })
        else
            null;

        const route_path = if (current_path.len == 0)
            try allocator.dupe(u8, "/")
        else
            try allocator.dupe(u8, current_path);
        defer allocator.free(route_path);

        // In route path we can have users/[id]/profile in those such case convert to users/:id/profile
        var normalized_route_path = std.array_list.Managed(u8).init(allocator);
        for (route_path) |c| {
            if (c == '[') {
                try normalized_route_path.append(':');
            } else if (c != ']') {
                try normalized_route_path.append(c);
            }
            // skip ']' characters
        }

        // Only add route if it has a page or route handler (not just proxy)
        if (has_page or has_route) {
            const route = Route{
                .path = try normalized_route_path.toOwnedSlice(),
                .page_import = page_import,
                .route_import = route_import,
                .proxy_import = proxy_import,
                .layout_import = layout_import,
                .notfound_import = notfound_import,
                .error_import = error_import,
            };
            try routes.append(route);
        } else {
            normalized_route_path.deinit();
            if (page_import) |p| allocator.free(p);
            if (route_import) |r| allocator.free(r);
            if (proxy_import) |pr| allocator.free(pr);
            if (layout_import) |l| allocator.free(l);
            if (notfound_import) |n| allocator.free(n);
            if (error_import) |e| allocator.free(e);
        }
    }

    var dir = try std.fs.cwd().openDir(current_dir, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .directory) continue;
        if (std.mem.eql(u8, entry.name, ".zx")) continue;

        const child_dir = try std.fs.path.join(allocator, &.{ current_dir, entry.name });
        defer allocator.free(child_dir);

        const child_path = if (std.mem.eql(u8, current_path, "/"))
            try std.mem.concat(allocator, u8, &.{ "/", entry.name })
        else
            try std.mem.concat(allocator, u8, &.{ current_path, "/", entry.name });
        defer allocator.free(child_path);

        const child_import_prefix = try std.mem.concat(allocator, u8, &.{ import_prefix, "/", entry.name });
        defer allocator.free(child_import_prefix);

        try scanPagesRecursive(allocator, child_dir, child_path, layout_stack, child_import_prefix, routes);
    }

    if (current_layout_import) |layout| {
        _ = layout_stack.pop();
        allocator.free(layout);
    }
}

/// Scan routes directory for API route files (route.zig) and proxy middleware (proxy.zig)
fn scanRoutesRecursive(
    allocator: std.mem.Allocator,
    current_dir: []const u8,
    current_path: []const u8,
    import_prefix: []const u8,
    routes: *std.array_list.Managed(Route),
) !void {
    const route_file_path = try std.fs.path.join(allocator, &.{ current_dir, "route.zig" });
    defer allocator.free(route_file_path);

    const proxy_file_path = try std.fs.path.join(allocator, &.{ current_dir, "proxy.zig" });
    defer allocator.free(proxy_file_path);

    const has_route = blk: {
        std.fs.cwd().access(route_file_path, .{}) catch break :blk false;
        break :blk true;
    };

    const has_proxy = blk: {
        std.fs.cwd().access(proxy_file_path, .{}) catch break :blk false;
        break :blk true;
    };

    if (has_route) {
        const route_import = try std.mem.concat(allocator, u8, &.{ import_prefix, "/route.zig" });

        const proxy_import = if (has_proxy)
            try std.mem.concat(allocator, u8, &.{ import_prefix, "/proxy.zig" })
        else
            null;

        // Build the URL path from directory structure
        const route_path = if (current_path.len == 0)
            try allocator.dupe(u8, "/")
        else
            try allocator.dupe(u8, current_path);
        defer allocator.free(route_path);

        // Normalize route path: convert [id] to :id
        var normalized_route_path = std.array_list.Managed(u8).init(allocator);
        for (route_path) |c| {
            if (c == '[') {
                try normalized_route_path.append(':');
            } else if (c != ']') {
                try normalized_route_path.append(c);
            }
        }

        const route = Route{
            .path = try normalized_route_path.toOwnedSlice(),
            .route_import = route_import,
            .proxy_import = proxy_import,
        };
        try routes.append(route);
    }

    // Recurse into subdirectories
    var dir = std.fs.cwd().openDir(current_dir, .{ .iterate = true }) catch return;
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .directory) continue;
        if (std.mem.eql(u8, entry.name, ".zx")) continue;

        const child_dir = try std.fs.path.join(allocator, &.{ current_dir, entry.name });
        defer allocator.free(child_dir);

        const child_path = if (current_path.len == 0 or std.mem.eql(u8, current_path, "/"))
            try std.mem.concat(allocator, u8, &.{ "/", entry.name })
        else
            try std.mem.concat(allocator, u8, &.{ current_path, "/", entry.name });
        defer allocator.free(child_path);

        const child_import_prefix = try std.mem.concat(allocator, u8, &.{ import_prefix, "/", entry.name });
        defer allocator.free(child_import_prefix);

        try scanRoutesRecursive(allocator, child_dir, child_path, child_import_prefix, routes);
    }
}

// --- Transpilation --- //
fn transpileFile(
    allocator: std.mem.Allocator,
    global_components: *std.array_list.Managed(ClientComponentSerializable),
    opts: TranspileOptions,
    source_path: []const u8,
    output_path: []const u8,
) !void {
    const source = try std.fs.cwd().readFileAlloc(
        allocator,
        source_path,
        std.math.maxInt(usize),
    );
    defer allocator.free(source);

    const source_z = try allocator.dupeZ(u8, source);
    defer allocator.free(source_z);

    // Convert to relative path for deterministic component IDs and sourcemaps
    var relative_source_path: []const u8 = source_path;
    var rel_path_allocated = false;
    if (std.fs.path.isAbsolute(source_path)) {
        if (std.fs.cwd().realpathAlloc(allocator, ".")) |cwd| {
            defer allocator.free(cwd);
            if (relativePath(allocator, cwd, source_path)) |rel| {
                relative_source_path = rel;
                rel_path_allocated = true;
            } else |_| {}
        } else |_| {}
    }
    defer if (rel_path_allocated) allocator.free(relative_source_path);

    var result = try zx.Ast.parse(allocator, source_z, .{ .path = relative_source_path, .map = opts.map });
    defer result.deinit(allocator);

    // Extract route from source path
    const component_route = try extractRouteFromPath(allocator, relative_source_path);
    defer allocator.free(component_route);

    // Append components from this file to the global list
    for (result.client_components.items) |component| {
        const cloned_id = try allocator.dupe(u8, component.id);
        const cloned_name = try allocator.dupe(u8, component.name);

        var cloned_path: []const u8 = undefined;
        var cloned_import: []const u8 = undefined;
        var cloned_route: []const u8 = undefined;

        switch (component.type) {
            .client => {
                // For .client components, use the output .zig file path (relative to output_dir)
                const output_rel_to_dir = try relativePath(allocator, opts.outdir, output_path);
                defer allocator.free(output_rel_to_dir);

                // Remove leading "./" if present
                const clean_path = if (std.mem.startsWith(u8, output_rel_to_dir, "./"))
                    output_rel_to_dir[2..]
                else
                    output_rel_to_dir;

                cloned_path = try allocator.dupe(u8, clean_path);

                // Generate Zig import with componentWithProps wrapper for props hydration
                // Format: zx.componentWithProps(@import("path").ComponentName)
                // Placeholders:
                //   "@ and @" - markers to strip outer quotes from ZON serialization
                //   @@@ - literal @ (for @import)
                //   @@ - literal " (for quotes inside @import())
                const import_str = try std.fmt.allocPrint(allocator, "@zx.Client.ComponentMeta.init(@@@import(@@{s}@@).{s})@", .{ clean_path, component.name });
                cloned_import = import_str;
            },
            .react => {
                // For .react components, the path is relative to project root (e.g., site/pages/...).
                const abs_component_path = std.fs.cwd().realpathAlloc(allocator, component.path) catch |err| blk: {
                    // Fallback to resolving relative to CWD if realpath fails
                    std.log.warn("Warning: could not get realpath for {s}: {}\n", .{ component.path, err });
                    const cwd = std.fs.cwd().realpathAlloc(allocator, ".") catch |err2| {
                        std.log.err("Error: realpath(.) failed: {}\n", .{err2});
                        break :blk try allocator.dupe(u8, component.path);
                    };
                    defer allocator.free(cwd);
                    break :blk try std.fs.path.resolve(allocator, &.{ cwd, component.path });
                };
                defer allocator.free(abs_component_path);

                const import_str = try std.fmt.allocPrint(allocator, "@async () => (await import('{s}')).default@", .{abs_component_path});
                cloned_path = try allocator.dupe(u8, component.path);
                cloned_import = import_str;
            },
            else => return error.InvalidComponentType,
        }

        // Clone the route for this component
        cloned_route = try allocator.dupe(u8, component_route);

        try global_components.append(.{
            .type = component.type,
            .id = cloned_id,
            .name = cloned_name,
            .path = cloned_path,
            .import = cloned_import,
            .route = cloned_route,
        });
    }

    if (std.fs.path.dirname(output_path)) |dir| {
        std.fs.cwd().makePath(dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    try std.fs.cwd().writeFile(.{
        .sub_path = output_path,
        .data = result.zig_source,
    });

    // Handle sourcemap based on config
    if (result.sourcemap) |sm| {
        switch (opts.map) {
            .none => {},
            .file => |map_path| {
                // Write sourcemap to a separate file
                const sourcemap_json = try sm.toJSON(
                    allocator,
                    output_path,
                    relative_source_path,
                    source,
                    result.zig_source,
                );
                defer allocator.free(sourcemap_json);

                try std.fs.cwd().writeFile(.{
                    .sub_path = map_path,
                    .data = sourcemap_json,
                });

                if (opts.verbose) std.debug.print("Sourcemap: {s}\n", .{map_path});
            },
            .inlined => {
                // For inlined sourcemaps, append to the generated file as a comment
                const sourcemap_json = try sm.toJSON(
                    allocator,
                    output_path,
                    relative_source_path,
                    source,
                    null,
                );
                defer allocator.free(sourcemap_json);

                const base64_encoded = try base64Encode(allocator, sourcemap_json);
                defer allocator.free(base64_encoded);

                const inline_comment = try std.fmt.allocPrint(
                    allocator,
                    "\n//# sourceMappingURL=data:application/json;base64,{s}\n",
                    .{base64_encoded},
                );
                defer allocator.free(inline_comment);

                // Append to the output file
                var file = try std.fs.cwd().openFile(output_path, .{ .mode = .read_write });
                defer file.close();
                try file.seekFromEnd(0);
                try file.writeAll(inline_comment);

                if (opts.verbose) std.debug.print("Inlined sourcemap in: {s}\n", .{output_path});
            },
        }
    }

    if (opts.verbose) std.debug.print("Transpiled: {s} -> {s}\n", .{ source_path, output_path });
}

fn transpileDirectory(
    allocator: std.mem.Allocator,
    global_components: *std.array_list.Managed(ClientComponentSerializable),
    input_files: *std.array_list.Managed([]const u8),
    opts: TranspileOptions,
    progress: std.Progress.Node,
) !void {
    var task = progress.start("Transpiling .zx files", 0);
    defer task.end();

    var dir = try std.fs.cwd().openDir(opts.path, .{ .iterate = true });
    defer dir.close();

    const output_dir_relative = try getOutputDirRelativePath(allocator, opts.path, opts.outdir);
    defer if (output_dir_relative) |rel| allocator.free(rel);

    const sep = std.fs.path.sep_str;

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        task.completeOne();
        var actual_kind = entry.kind;
        if (entry.kind == .sym_link) {
            const entry_stat = dir.statFile(entry.path) catch continue;
            actual_kind = entry_stat.kind;
        }

        if (actual_kind != .file) continue;

        if (output_dir_relative) |rel| {
            if (std.mem.startsWith(u8, entry.path, rel)) {
                if (entry.path.len == rel.len) {
                    continue;
                }
                if (std.mem.startsWith(u8, entry.path[rel.len..], sep)) {
                    continue;
                }
            }
        }

        const is_zx = std.mem.endsWith(u8, entry.path, ".zx");

        const input_path = try std.fs.path.join(allocator, &.{ opts.path, entry.path });
        defer allocator.free(input_path);

        if (is_zx) {
            const output_rel_path = try std.mem.concat(allocator, u8, &.{
                entry.path[0 .. entry.path.len - (".zx").len],
                ".zig",
            });
            defer allocator.free(output_rel_path);

            const output_path = try std.fs.path.join(allocator, &.{ opts.outdir, output_rel_path });
            defer allocator.free(output_path);

            // Track this input for the dep file (absolute path for Make format)
            const abs_input = std.fs.cwd().realpathAlloc(allocator, input_path) catch
                try allocator.dupe(u8, input_path);
            try input_files.append(abs_input);

            // Cache file alongside the .zig output (not .zig extension so compiler ignores it)
            const cache_path = try std.mem.concat(allocator, u8, &.{ output_path, ".zxcache" });
            defer allocator.free(cache_path);

            // Check if output is up-to-date (mtime comparison + cache file existence)
            const should_skip = blk: {
                const input_stat = std.fs.cwd().statFile(input_path) catch break :blk false;
                const output_stat = std.fs.cwd().statFile(output_path) catch break :blk false;
                std.fs.cwd().access(cache_path, .{}) catch break :blk false;
                break :blk output_stat.mtime >= input_stat.mtime;
            };

            if (should_skip) {
                readComponentCache(allocator, cache_path, global_components) catch |err| {
                    std.debug.print("Warning: Failed to read component cache for {s}: {}\n", .{ input_path, err });
                };
                if (opts.verbose) std.debug.print("Skipped (up-to-date): {s}\n", .{input_path});
                continue;
            }

            const components_before = global_components.items.len;
            transpileFile(allocator, global_components, opts, input_path, output_path) catch |err| {
                global_components.items.len = components_before;
                std.debug.print("Error transpiling {s}: {}\n", .{ input_path, err });
                continue;
            };

            writeComponentCache(allocator, cache_path, global_components.items[components_before..]) catch |err| {
                std.debug.print("Warning: Failed to write component cache for {s}: {}\n", .{ input_path, err });
            };

            // Also copy the original .zx file if copy_embedded_sources is enabled
            if (opts.copy_embedded_sources) {
                const zx_output_path = try std.fs.path.join(allocator, &.{ opts.outdir, entry.path });
                defer allocator.free(zx_output_path);

                if (std.fs.path.dirname(zx_output_path)) |parent| {
                    std.fs.cwd().makePath(parent) catch |err| switch (err) {
                        error.PathAlreadyExists => {},
                        else => {
                            std.debug.print("Error creating directory {s}: {}\n", .{ parent, err });
                            continue;
                        },
                    };
                }

                std.fs.cwd().copyFile(input_path, std.fs.cwd(), zx_output_path, .{}) catch |err| {
                    std.debug.print("Warning: Could not copy .zx source {s}: {}\n", .{ input_path, err });
                    continue;
                };
                if (opts.verbose) std.debug.print("Copied source: {s} -> {s}\n", .{ input_path, zx_output_path });
            }
        } else {
            // Copy all non-.zx files from the site directory, excluding reserved files
            const basename = getBasename(entry.path);

            // Skip files inside node_modules directory
            if (std.mem.startsWith(u8, entry.path, "node_modules" ++ sep) or
                std.mem.indexOf(u8, entry.path, sep ++ "node_modules" ++ sep) != null)
            {
                continue;
            }

            const is_root_file = std.mem.indexOf(u8, entry.path, sep) == null;
            if (is_root_file) {
                const reserved_files = [_][]const u8{ "components.zig", "app.zig", "client.zig" };
                var is_reserved = false;
                for (reserved_files) |reserved| {
                    if (std.mem.eql(u8, basename, reserved)) {
                        std.debug.print("Warning: '{s}' is a reserved file name and will not be copied\n", .{input_path});
                        is_reserved = true;
                        break;
                    }
                }

                // Skip reserved files and main.zig at root level
                if (is_reserved or std.mem.eql(u8, basename, "main.zig")) {
                    continue;
                }
            }

            const output_path = try std.fs.path.join(allocator, &.{ opts.outdir, entry.path });
            defer allocator.free(output_path);

            if (std.fs.path.dirname(output_path)) |parent| {
                std.fs.cwd().makePath(parent) catch |err| switch (err) {
                    error.PathAlreadyExists => {},
                    else => {
                        std.debug.print("Error creating directory {s}: {}\n", .{ parent, err });
                        continue;
                    },
                };
            }

            try std.fs.cwd().copyFile(input_path, std.fs.cwd(), output_path, .{});
            if (opts.verbose) std.debug.print("Copied: {s} -> {s}\n", .{ input_path, output_path });
        }
    }
}

const TranspileOptions = struct {
    path: []const u8,
    outdir: []const u8,
    verbose: bool,
    map: zx.Ast.ParseOptions.MapMode = .none,
    copy_embedded_sources: bool = false,
    rootdir: ?[]const u8 = null,
    dep_file: ?[]const u8 = null,
};

fn transpileCommand(allocator: std.mem.Allocator, opts: TranspileOptions) !void {
    // Start root progress for the entire transpile operation
    var progress = std.Progress.start(.{ .root_name = "Transpile" });
    defer progress.end();

    var all_client_cmps = std.array_list.Managed(ClientComponentSerializable).init(allocator);
    defer {
        for (all_client_cmps.items) |*component| {
            allocator.free(component.id);
            allocator.free(component.name);
            allocator.free(component.path);
            allocator.free(component.import);
            allocator.free(component.route);
        }
        all_client_cmps.deinit();
    }

    var input_files = std.array_list.Managed([]const u8).init(allocator);
    defer {
        for (input_files.items) |f| allocator.free(f);
        input_files.deinit();
    }

    const stat = std.fs.cwd().statFile(opts.path) catch |err| switch (err) {
        error.IsDir => std.fs.File.Stat{ .kind = .directory, .size = 0, .mode = 0, .atime = 0, .mtime = 0, .ctime = 0, .inode = 0 },
        else => {
            std.debug.print("Error: Could not access path '{s}': {}\n", .{ opts.path, err });
            return err;
        },
    };

    switch (stat.kind) {
        .directory => {
            try transpileDirectory(allocator, &all_client_cmps, &input_files, opts, progress);
        },
        .file => {
            const is_zx = std.mem.endsWith(u8, opts.path, ".zx");

            if (!is_zx) {
                std.debug.print("Error: File must have .zx extension, got '{s}'\n", .{opts.path});
                return error.InvalidFileExtension;
            }

            var task = progress.start("Transpiling file", 1);
            defer task.end();

            const basename = getBasename(opts.path);
            const output_rel_path = try std.mem.concat(allocator, u8, &.{ basename[0 .. basename.len - (".zx").len], ".zig" });
            defer allocator.free(output_rel_path);
            const outpath = try std.fs.path.join(allocator, &.{ opts.outdir, output_rel_path });
            defer allocator.free(outpath);

            try transpileFile(allocator, &all_client_cmps, opts, opts.path, outpath);
            task.completeOne();
        },
        else => {
            std.debug.print("Error: Path must be a file or directory\n", .{});
            return error.InvalidPath;
        },
    }

    // Write dep file (Make format) so zig build can track .zx inputs for caching
    if (opts.dep_file) |dep_file_path| {
        writeDepFile(allocator, dep_file_path, dep_file_path, input_files.items) catch |err| {
            std.debug.print("Warning: Failed to write dep file: {}\n", .{err});
        };
    }

    // Generate routes
    genRoutes(allocator, opts.outdir, opts.rootdir, opts.verbose) catch |err| {
        std.debug.print("Warning: Failed to generate meta.zig: {}\n", .{err});
    };

    // --- @rendering -> Client Side Rendering Related Files Generation --- //
    var react_cmps = std.array_list.Managed(ClientComponentSerializable).init(allocator);
    defer react_cmps.deinit();
    var client_cmps = std.array_list.Managed(ClientComponentSerializable).init(allocator);
    defer client_cmps.deinit();

    for (all_client_cmps.items) |component| {
        switch (component.type) {
            .react => try react_cmps.append(component),
            .client => try client_cmps.append(component),
            else => return error.InvalidComponentType,
        }
    }

    // @rendering={.react}
    genReactComponents(allocator, react_cmps.items, opts.outdir, opts.verbose) catch |err| {
        std.debug.print("Warning: Failed to generate main.tsx: {}\n", .{err});
    };

    // @rendering={.client}
    genClientComponents(allocator, client_cmps.items, opts.outdir, opts.verbose) catch |err| {
        std.debug.print("Warning: Failed to generate main_wasm.zig: {}\n", .{err});
    };
}
