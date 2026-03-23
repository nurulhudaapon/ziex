pub fn register(writer: *std.Io.Writer, reader: *std.Io.Reader, allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(writer, reader, allocator, .{
        .name = "bundle",
        .description = "Bundle the site into deployable directory",
    }, bundle);

    try cmd.addFlag(outdir_flag);
    try cmd.addFlag(flag.binpath_flag);
    try cmd.addFlag(flag.build_args);
    try cmd.addFlag(docker_flag);
    try cmd.addFlag(docker_compose_flag);

    return cmd;
}

const outdir_flag = zli.Flag{
    .name = "outdir",
    .shortcut = "o",
    .description = "Output directory",
    .type = .String,
    .default_value = .{ .String = "bundle" },
};

const docker_flag = zli.Flag{
    .name = "docker",
    .shortcut = "d",
    .description = "Include Dockerfile in the bundle",
    .type = .Bool,
    .hidden = true,
    .default_value = .{ .Bool = false },
};

const docker_compose_flag = zli.Flag{
    .name = "docker-compose",
    .shortcut = "dc",
    .description = "Include docker-compose.yml and Dockerfile in the bundle",
    .type = .Bool,
    .hidden = true,
    .default_value = .{ .Bool = false },
};

fn bundle(ctx: zli.CommandContext) !void {
    const outdir = ctx.flag("outdir", []const u8);
    const binpath = ctx.flag("binpath", []const u8);
    const docker = ctx.flag("docker", bool);
    const docker_compose = ctx.flag("docker-compose", bool);
    const build_args = ctx.flag("build-args", []const u8);

    var app_meta = util.findprogram(ctx.allocator, binpath) catch |err| {
        if (err == error.FileNotFound or err == error.ProgramNotFound) {
            try ctx.writer.print("Run \x1b[34mzig build\x1b[0m to build the ZX executable first!\n", .{});
            return;
        }
        try ctx.writer.print("Error finding ZX executable! {any}\n", .{err});
        return;
    };
    defer std.zon.parse.free(ctx.allocator, app_meta);

    const appoutdir = app_meta.rootdir orelse "site/.zx";
    const final_binpath = app_meta.binpath orelse binpath;

    var printer = tui.Printer.init(ctx.allocator, .{ .file_path_mode = .flat, .file_tree_max_depth = 1 });
    defer printer.deinit();

    printer.header("{s} Bundling ZX site!", .{tui.Printer.emoji("○")});
    printer.info("{s}", .{outdir});

    var aw = std.Io.Writer.Allocating.init(ctx.allocator);
    defer aw.deinit();
    try app_meta.serialize(&aw.writer);
    log.debug("Bundling ZX site! {s}", .{aw.written()});

    log.debug("Outdir: {s}", .{outdir});

    const bin_name = std.fs.path.basename(final_binpath);
    const port = app_meta.config.server.port orelse 3000;
    const port_str = try std.fmt.allocPrint(ctx.allocator, "{d}", .{port});
    defer ctx.allocator.free(port_str);
    const dest_binpath = try std.fs.path.join(ctx.allocator, &.{ outdir, bin_name });
    defer ctx.allocator.free(dest_binpath);
    log.debug("Copying bin from {s} to outdir {s}", .{ final_binpath, dest_binpath });

    if (!(docker or docker_compose)) {
        std.fs.cwd().makePath(outdir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        try std.fs.cwd().copyFile(final_binpath, std.fs.cwd(), dest_binpath, .{});
        printer.filepath(bin_name);

        const static_outdir = try std.fs.path.join(ctx.allocator, &.{ outdir, "static" });
        defer ctx.allocator.free(static_outdir);
        log.debug("Copying static directory! {s}", .{appoutdir});
        util.copydirs(ctx.allocator, appoutdir, &.{"."}, static_outdir, false, &printer) catch |err| {
            std.log.err("Failed to copy static directories: {any}", .{err});
        };

        // Clean up old directories if they exist
        const old_public = try std.fs.path.join(ctx.allocator, &.{ outdir, "public" });
        const old_assets = try std.fs.path.join(ctx.allocator, &.{ outdir, "assets" });
        defer ctx.allocator.free(old_public);
        defer ctx.allocator.free(old_assets);
        std.fs.cwd().deleteTree(old_public) catch {};
        std.fs.cwd().deleteTree(old_assets) catch {};
    }

    // Delete {outdir}/.well-known/_zx if it exists
    const assets_zx_path = try std.fs.path.join(ctx.allocator, &.{ outdir, ".well-known", "_zx" });
    defer ctx.allocator.free(assets_zx_path);
    std.fs.cwd().deleteTree(assets_zx_path) catch |err| switch (err) {
        else => {},
    };

    const compose_content = @embedFile("init/template/compose.yml");
    const dockerfile_content = @embedFile("init/template/Dockerfile");

    if (docker or docker_compose) {
        // Replace $BIN_NAME
        const dockerfile_content_with_bin_name = try std.mem.replaceOwned(u8, ctx.allocator, dockerfile_content, "$BIN_NAME", bin_name);
        const compose_content_with_bin_name = try std.mem.replaceOwned(u8, ctx.allocator, compose_content, "$BIN_NAME", bin_name);
        defer ctx.allocator.free(dockerfile_content_with_bin_name);
        defer ctx.allocator.free(compose_content_with_bin_name);

        // Replace $BUILD_ARGS
        const dockerfile_content_with_build_args = try std.mem.replaceOwned(u8, ctx.allocator, dockerfile_content_with_bin_name, "$BUILD_ARGS", build_args);
        const compose_content_with_build_args = try std.mem.replaceOwned(u8, ctx.allocator, compose_content_with_bin_name, "$BUILD_ARGS", build_args);
        defer ctx.allocator.free(dockerfile_content_with_build_args);
        defer ctx.allocator.free(compose_content_with_build_args);

        // Replace $PORT in template/compose.yml with port
        const compose_content_with_port = try std.mem.replaceOwned(u8, ctx.allocator, compose_content_with_build_args, "$PORT", port_str);
        defer ctx.allocator.free(compose_content_with_port);

        const dockerfile_path = try std.fs.path.join(ctx.allocator, &.{"Dockerfile"});
        const compose_path = try std.fs.path.join(ctx.allocator, &.{"compose.yml"});
        const dockerignore_path = try std.fs.path.join(ctx.allocator, &.{".dockerignore"});
        defer ctx.allocator.free(dockerfile_path);
        defer ctx.allocator.free(compose_path);
        defer ctx.allocator.free(dockerignore_path);

        try std.fs.cwd().writeFile(.{ .sub_path = dockerfile_path, .data = dockerfile_content_with_build_args });
        printer.filepath(std.fs.path.basename(dockerfile_path));
        if (docker_compose) {
            try std.fs.cwd().writeFile(.{ .sub_path = compose_path, .data = compose_content_with_port });
            printer.filepath(std.fs.path.basename(compose_path));
        }
        try std.fs.cwd().writeFile(.{ .sub_path = dockerignore_path, .data = @embedFile("init/template/.dockerignore") });
        printer.filepath(std.fs.path.basename(dockerignore_path));
    }

    if (docker or docker_compose) {
        if (docker_compose) {
            printer.footer("Now run {s}\n{s}docker compose up -d{s}", .{ tui.Printer.emoji("→"), tui.Colors.cyan, tui.Colors.reset });
        } else {
            printer.footer("Now run {s}\n\n{s}docker build -t {s} . \ndocker run -p {d}:{d} {s}{s}", .{ tui.Printer.emoji("→"), tui.Colors.cyan, bin_name, port, port, bin_name, tui.Colors.reset });
        }
    } else {
        printer.footer("Now run {s}\n\n{s}(cd {s} && ./{s} --rootdir ./static){s}", .{ tui.Printer.emoji("→"), tui.Colors.cyan, outdir, bin_name, tui.Colors.reset });
    }
}

const std = @import("std");
const zli = @import("zli");
const util = @import("shared/util.zig");
const flag = @import("shared/flag.zig");
const zx = @import("zx");
const tui = @import("../tui/main.zig");
const log = std.log.scoped(.cli);
