pub fn register(writer: *std.Io.Writer, reader: *std.Io.Reader, allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(writer, reader, allocator, .{
        .name = "init",
        .description = "Initialize a new ZX project in the current directory",
    }, init);

    try cmd.addPositionalArg(init_path_arg);
    try cmd.addFlag(template_flag);
    try cmd.addFlag(force_flag);
    try cmd.addFlag(existing_flag);

    return cmd;
}

const template_flag = zli.Flag{
    .name = "template",
    .shortcut = "t",
    .description = "Template to use (default, react)",
    .type = .String,
    .default_value = .{ .String = "default" },
};

const force_flag = zli.Flag{
    .name = "force",
    .shortcut = "f",
    .description = "Force initialization even if the directory is not empty",
    .type = .Bool,
    .default_value = .{ .Bool = false },
};

const existing_flag = zli.Flag{
    .name = "existing",
    .description = "Initialize ZX in an existing project",
    .type = .Bool,
    .default_value = .{ .Bool = false },
};

const init_path_arg = zli.PositionalArg{
    .name = "path",
    .description = "Path to initialize the project in (default: current directory)",
    .required = false,
};

fn init(ctx: zli.CommandContext) !void {
    const t_val = ctx.flag("template", []const u8);
    const force_init = ctx.flag("force", bool);
    const existing_init = ctx.flag("existing", bool);
    const init_path = std.mem.trim(u8, ctx.getArg("path") orelse ".", " ");

    var printer = tui.Printer.init(ctx.allocator, .{ .file_path_mode = .flat, .file_tree_max_depth = 1 });
    defer printer.deinit();

    // Validations
    const is_clean_dir = try isDirEmpty(init_path);
    const has_init_path_arg = init_path.len > 0 and !std.mem.eql(u8, init_path, ".");
    if (!is_clean_dir and !force_init and !existing_init) {
        printer.warning("Directory is not empty.", .{});
        try ctx.writer.print("\nYou may want either:\n\n", .{});
        if (!has_init_path_arg)
            try ctx.writer.print("  {s}zx init{s} {s}{s}{s}{s}  {s}# Create in a new directory{s}\n\n", .{
                colors.cyan,
                colors.reset,
                colors.bold,
                colors.gray,
                "my-app",
                colors.reset,
                colors.gray,
                colors.reset,
            });
        try ctx.writer.print("  {s}zx init{s} {s}{s}{s}{s}--force{s}  {s}# Create in current directory, overriding existing files{s}\n\n", .{
            colors.cyan,
            colors.reset,
            colors.bold,
            colors.gray,
            if (has_init_path_arg) init_path else "",
            if (has_init_path_arg) " " else "",
            colors.reset,
            colors.gray,
            colors.reset,
        });
        return;
    }

    if (force_init and !is_clean_dir) {
        std.debug.print("{s}Initializing with existing files, overriding if files already exist.{s}\n", .{ colors.yellow, colors.reset });
    }

    const template_name = if (std.meta.stringToEnum(TemplateFile.Name, t_val)) |name| name else {
        std.debug.print("\x1b[33mUnknown template:\x1b[0m {s}\n\nTemplates:\n", .{t_val});

        for (std.enums.values(TemplateFile.Name)) |name| {
            std.debug.print("  - \x1b[34m{s}\x1b[0m\n", .{@tagName(name)});
        }
        std.debug.print("\n", .{});
        return;
    };

    printer.header("{s} Initializing ZX project!", .{tui.Printer.emoji("○")});
    printer.info("[{s}]", .{@tagName(template_name)});

    try std.fs.cwd().makePath(init_path);
    for (templates) |template| {
        if (template.name != null and template.name.? != template_name) continue;

        const output_path = try std.fs.path.join(ctx.allocator, &.{ init_path, template.path });
        defer ctx.allocator.free(output_path);

        // Skip if file exists and existing flag is set
        if (existing_init) {
            const file_exists = blk: {
                std.fs.cwd().access(output_path, .{}) catch |err| switch (err) {
                    error.FileNotFound => break :blk false,
                    else => continue,
                };
                break :blk true;
            };
            if (file_exists) continue;
        }

        if (std.fs.path.dirname(output_path)) |parent_dir| {
            try std.fs.cwd().makePath(parent_dir);
        }

        var file = try std.fs.cwd().createFile(output_path, .{ .truncate = true });

        printer.filepath(template.path);
        defer file.close();

        if (template.lines) |lines| {
            var line_iter = std.mem.splitScalar(u8, template.content, '\n');
            var line_n: usize = 1;

            while (line_iter.next()) |line| {
                for (lines) |line_range| {
                    const start, const end = line_range;
                    if (line_n < start or line_n > end) continue;
                    try file.writeAll(line);
                    try file.writeAll("\n");
                }

                line_n += 1;
            }
        } else {
            try file.writeAll(template.content);
        }
    }

    if (has_init_path_arg) {
        const suggested_cmd = try std.fmt.allocPrint(ctx.allocator, "cd {s} && zig build dev", .{init_path});
        defer ctx.allocator.free(suggested_cmd);
        printer.footer("Now run {s}\n\n{s}{s}{s}", .{ tui.Printer.emoji("→"), colors.cyan, suggested_cmd, colors.reset });
    } else {
        printer.footer("Now run {s}\n\n{s}", .{ tui.Printer.emoji("→"), colors.Fns.cyan("zig build dev") });
    }
}

pub fn isDirEmpty(path: []const u8) !bool {
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return true,
        else => return err,
    };
    defer dir.close();

    var iter = dir.iterate();
    return try iter.next() == null;
}

const TemplateFile = struct {
    const Name = enum { default, react, docker };

    name: ?Name = null,
    path: []const u8,
    content: []const u8,
    description: ?[]const u8 = "",

    /// Lines to include from the template file
    /// Range of lines to include
    lines: ?[]const struct { u32, u32 } = null,
};

const template_dir = "init/template";

const templates = [_]TemplateFile{
    // Shared
    .{ .path = "build.zig.zon", .content = @embedFile(template_dir ++ "/build.zig.zon") },
    .{ .path = "build.zig", .content = @embedFile(template_dir ++ "/build.zig") },
    .{ .path = "app/main.zig", .content = @embedFile(template_dir ++ "/app/main.zig") },
    .{ .path = "README.md", .content = @embedFile(template_dir ++ "/README.md") },
    .{ .path = "app/assets/style.css", .content = @embedFile(template_dir ++ "/app/assets/style.css") },
    .{ .path = "app/public/favicon.ico", .content = @embedFile(template_dir ++ "/app/public/favicon.ico") },
    .{ .path = "app/pages/about/page.zx", .content = @embedFile(template_dir ++ "/app/pages/about/page.zx") },
    .{ .path = "app/pages/layout.zx", .content = @embedFile(template_dir ++ "/app/pages/layout.zx") },
    .{ .path = ".gitignore", .content = @embedFile(template_dir ++ "/.gitignore") },
    .{ .path = ".gitattributes", .content = @embedFile(template_dir ++ "/.gitattributes") },

    // Default (SSR + CSR)
    .{ .name = .default, .path = "app/pages/page.zx", .content = @embedFile(template_dir ++ "/app/pages/page.zx") },
    .{ .name = .default, .path = "app/pages/client.zx", .content = @embedFile(template_dir ++ "/app/pages/client.zx") },

    // Ziex + React (SSR + CSR)
    .{ .name = .react, .path = "app/pages/page.zx", .content = @embedFile(template_dir ++ "/app/pages/page+react.zx") },
    .{ .name = .react, .path = "app/pages/client.zx", .content = @embedFile(template_dir ++ "/app/pages/client.zx") },
    .{ .name = .react, .path = "app/pages/client.tsx", .content = @embedFile(template_dir ++ "/app/pages/client.tsx") },
    .{ .name = .react, .path = "app/main.ts", .content = @embedFile(template_dir ++ "/app/main.ts"), .lines = &.{ .{ 1, 4 }, .{ 7, 7 }, .{ 11, 18 } } },
    .{ .name = .react, .path = "package.json", .content = @embedFile(template_dir ++ "/package.json") },
    .{ .name = .react, .path = "tsconfig.json", .content = @embedFile(template_dir ++ "/tsconfig.json") },

    // Docker
    .{ .name = .docker, .path = "compose.yml", .content = @embedFile(template_dir ++ "/compose.yml") },
    .{ .name = .docker, .path = "Dockerfile", .content = @embedFile(template_dir ++ "/Dockerfile") },
    .{ .name = .docker, .path = ".dockerignore", .content = @embedFile(template_dir ++ "/Dockerfile") },
};

const std = @import("std");
const zli = @import("zli");
const tui = @import("../tui/main.zig");
const colors = tui.Colors;
