pub fn register(writer: *std.Io.Writer, reader: *std.Io.Reader, allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(writer, reader, allocator, .{
        .name = "init",
        .description = "Initialize a new ZX project in the current directory",
    }, init);

    try cmd.addPositionalArg(init_path_arg);
    try cmd.addFlag(template_flag);
    try cmd.addFlag(force_flag);

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

const init_path_arg = zli.PositionalArg{
    .name = "path",
    .description = "Path to initialize the project in (default: current directory)",
    .required = false,
};

fn init(ctx: zli.CommandContext) !void {
    const t_val = ctx.flag("template", []const u8);
    const force_init = ctx.flag("force", bool);
    const init_path = std.mem.trim(u8, ctx.getArg("path") orelse ".", " ");

    var printer = tui.Printer.init(ctx.allocator, .{ .file_path_mode = .flat, .file_tree_max_depth = 1 });
    defer printer.deinit();

    // Validations
    const is_clean_dir = try isDirEmpty(init_path);
    const has_init_path_arg = init_path.len > 0 and !std.mem.eql(u8, init_path, ".");
    if (!is_clean_dir and !force_init) {
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
        const suggested_cmd = try std.fmt.allocPrint(ctx.allocator, "cd {s} && zx dev", .{init_path});
        defer ctx.allocator.free(suggested_cmd);
        printer.footer("Now run {s}\n\n{s}{s}{s}", .{ tui.Printer.emoji("→"), colors.cyan, suggested_cmd, colors.reset });
    } else {
        printer.footer("Now run {s}\n\n{s}", .{ tui.Printer.emoji("→"), colors.Fns.cyan("zx dev") });
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
    const Name = enum { default, react, wasm, react_wasm };

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
    .{ .path = ".vscode/extensions.json", .content = @embedFile(template_dir ++ "/.vscode/extensions.json") },
    .{ .path = "build.zig.zon", .content = @embedFile(template_dir ++ "/build.zig.zon") },
    // .{ .path = "build.zig", .content = @embedFile(template_dir ++ "/build.zig"), .lines = &.{ .{ 1, 28 }, .{ 30, 32 } } },
    .{ .path = "README.md", .content = @embedFile(template_dir ++ "/README.md") },
    .{ .path = "site/assets/style.css", .content = @embedFile(template_dir ++ "/site/assets/style.css") },
    .{ .path = "site/public/favicon.ico", .content = @embedFile(template_dir ++ "/site/public/favicon.ico") },
    .{ .path = "site/pages/about/page.zx", .content = @embedFile(template_dir ++ "/site/pages/about/page.zx") },
    .{ .path = "site/pages/layout.zx", .content = @embedFile(template_dir ++ "/site/pages/layout.zx") },
    .{ .path = "src/root.zig", .content = @embedFile(template_dir ++ "/src/root.zig") },
    .{ .path = ".gitignore", .content = @embedFile(template_dir ++ "/.gitignore") },

    // Default (SSR)
    .{ .name = .default, .path = "build.zig", .content = @embedFile(template_dir ++ "/build.zig"), .lines = &.{ .{ 1, 29 }, .{ 31, 33 } } },
    .{ .name = .default, .path = "site/main.zig", .content = @embedFile(template_dir ++ "/site/main.zig") },
    .{ .name = .default, .path = "site/pages/page.zx", .content = @embedFile(template_dir ++ "/site/pages/page.zx") },

    // React (CSR)
    .{ .name = .react, .path = "build.zig", .content = @embedFile(template_dir ++ "/build.zig"), .lines = &.{ .{ 1, 29 }, .{ 31, 33 } } },
    .{ .name = .react, .path = "site/main.zig", .content = @embedFile(template_dir ++ "/site/main.zig"), .lines = &.{ .{ 1, 3 }, .{ 5, 8 }, .{ 11, 21 } } },
    .{ .name = .react, .path = "site/main.ts", .content = @embedFile(template_dir ++ "/site/main.ts"), .lines = &.{ .{ 1, 4 }, .{ 7, 7 }, .{ 11, 18 } } },
    .{ .name = .react, .path = "site/pages/page.zx", .content = @embedFile(template_dir ++ "/site/pages/page+react.zx") },
    .{ .name = .react, .path = "site/pages/client.tsx", .content = @embedFile(template_dir ++ "/site/pages/client.tsx") },
    .{ .name = .react, .path = "package.json", .content = @embedFile(template_dir ++ "/package.json") },
    .{ .name = .react, .path = "tsconfig.json", .content = @embedFile(template_dir ++ "/tsconfig.json") },

    // WASM (CSR)
    .{ .name = .wasm, .path = "build.zig", .content = @embedFile(template_dir ++ "/build.zig") },
    .{ .name = .wasm, .path = "site/main.zig", .content = @embedFile(template_dir ++ "/site/main.zig") },
    .{ .name = .wasm, .path = "site/assets/main.wasm.js", .content = @embedFile(template_dir ++ "/site/assets/main.wasm.js") },
    .{ .name = .wasm, .path = "site/pages/page.zx", .content = @embedFile(template_dir ++ "/site/pages/page+wasm.zx") },
    .{ .name = .wasm, .path = "site/pages/client.zx", .content = @embedFile(template_dir ++ "/site/pages/client.zx") },

    // React + WASM
    .{ .name = .react_wasm, .path = "build.zig", .content = @embedFile(template_dir ++ "/build.zig"), .lines = &.{ .{ 1, 29 }, .{ 31, 33 } } },
    .{ .name = .react_wasm, .path = "site/main.zig", .content = @embedFile(template_dir ++ "/site/main.zig") },
    .{ .name = .react_wasm, .path = "site/main.ts", .content = @embedFile(template_dir ++ "/site/main.ts") },
    .{ .name = .react_wasm, .path = "site/pages/page.zx", .content = @embedFile(template_dir ++ "/site/pages/page+react_wasm.zx") },
    .{ .name = .react_wasm, .path = "site/pages/client.tsx", .content = @embedFile(template_dir ++ "/site/pages/client.tsx") },
    .{ .name = .react_wasm, .path = "site/pages/client.zx", .content = @embedFile(template_dir ++ "/site/pages/client.zx") },
    .{ .name = .react_wasm, .path = "package.json", .content = @embedFile(template_dir ++ "/package.json") },
    .{ .name = .react_wasm, .path = "tsconfig.json", .content = @embedFile(template_dir ++ "/tsconfig.json") },
};

const std = @import("std");
const zli = @import("zli");
const tui = @import("../tui/main.zig");
const colors = tui.Colors;
