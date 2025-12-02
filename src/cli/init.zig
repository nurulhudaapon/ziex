pub fn register(writer: *std.Io.Writer, reader: *std.Io.Reader, allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(writer, reader, allocator, .{
        .name = "init",
        .description = "Initialize a new ZX project in the current directory",
    }, init);

    try cmd.addFlag(template_flag);

    return cmd;
}

const template_flag = zli.Flag{
    .name = "template",
    .shortcut = "t",
    .description = "Template to use (default, react)",
    .type = .String,
    .default_value = .{ .String = "default" },
};

fn init(ctx: zli.CommandContext) !void {
    const t_val = ctx.flag("template", []const u8); // type-safe flag access

    const template_name = if (std.meta.stringToEnum(TemplateFile.Name, t_val)) |name| name else {
        std.debug.print("\x1b[33mUnknown template:\x1b[0m {s}\n\nTemplates:\n", .{t_val});

        for (std.enums.values(TemplateFile.Name)) |name| {
            std.debug.print("  - \x1b[34m{s}\x1b[0m\n", .{@tagName(name)});
        }
        std.debug.print("\n", .{});
        return;
    };

    var printer = tui.Printer.init(ctx.allocator, .{ .file_path_mode = .flat, .file_tree_max_depth = 1 });
    defer printer.deinit();

    printer.header("{s} Initializing ZX project!", .{tui.Printer.emoji("○")});
    printer.info("[{s}]", .{@tagName(template_name)});
    const output_dir = ".";

    try std.fs.cwd().makePath(output_dir);

    // Check if build.zig.zon already exists
    const build_zig_zon_path = try std.fs.path.join(ctx.allocator, &.{ output_dir, "build.zig.zon" });
    defer ctx.allocator.free(build_zig_zon_path);

    const cwd = std.fs.cwd();
    if (cwd.openFile(build_zig_zon_path, .{})) |file| {
        file.close();
        printer.warning("build.zig.zon already exists in {s}/. Skipping template initialization.", .{output_dir});
        return;
    } else |err| {
        switch (err) {
            error.FileNotFound => {},
            else => return err,
        }
    }

    for (templates) |template| {
        if (template.name != null and template.name.? != template_name) continue;

        const output_path = try std.fs.path.join(ctx.allocator, &.{ output_dir, template.path });
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

    printer.footer("Now run {s}\n\n{s}zig build serve{s}", .{ tui.Printer.emoji("→"), tui.Colors.cyan, tui.Colors.reset });
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
    .{ .path = "build.zig", .content = @embedFile(template_dir ++ "/build.zig") },
    .{ .path = "README.md", .content = @embedFile(template_dir ++ "/README.md") },
    .{ .path = "site/public/style.css", .content = @embedFile(template_dir ++ "/site/public/style.css") },
    .{ .path = "site/public/favicon.ico", .content = @embedFile(template_dir ++ "/site/public/favicon.ico") },
    .{ .path = "site/pages/about/page.zx", .content = @embedFile(template_dir ++ "/site/pages/about/page.zx") },
    .{ .path = "site/pages/layout.zx", .content = @embedFile(template_dir ++ "/site/pages/layout.zx") },
    .{ .path = "src/root.zig", .content = @embedFile(template_dir ++ "/src/root.zig") },
    .{ .path = ".gitignore", .content = @embedFile(template_dir ++ "/.gitignore") },

    // Default (SSR)
    .{ .name = .default, .path = "site/main.zig", .content = @embedFile(template_dir ++ "/site/main.zig"), .lines = &.{ .{ 1, 3 }, .{ 5, 8 }, .{ 11, 21 } } },
    .{ .name = .default, .path = "site/pages/page.zx", .content = @embedFile(template_dir ++ "/site/pages/page.zx") },

    // React (CSR)
    .{ .name = .react, .path = "site/main.zig", .content = @embedFile(template_dir ++ "/site/main.zig"), .lines = &.{ .{ 1, 3 }, .{ 5, 8 }, .{ 11, 21 } } },
    .{ .name = .react, .path = "site/main.ts", .content = @embedFile(template_dir ++ "/site/main.ts"), .lines = &.{ .{ 1, 4 }, .{ 7, 7 }, .{ 11, 18 } } },
    .{ .name = .react, .path = "site/pages/page.zx", .content = @embedFile(template_dir ++ "/site/pages/page+react.zx") },
    .{ .name = .react, .path = "site/pages/client.tsx", .content = @embedFile(template_dir ++ "/site/pages/client.tsx") },
    .{ .name = .react, .path = "package.json", .content = @embedFile(template_dir ++ "/package.json") },
    .{ .name = .react, .path = "tsconfig.json", .content = @embedFile(template_dir ++ "/tsconfig.json") },

    // WASM (CSR)
    .{ .name = .wasm, .path = "site/main.zig", .content = @embedFile(template_dir ++ "/site/main.zig") },
    .{ .name = .wasm, .path = "site/main.ts", .content = @embedFile(template_dir ++ "/site/main.ts"), .lines = &.{ .{ 5, 5 }, .{ 8, 10 } } },
    .{ .name = .wasm, .path = "site/pages/page.zx", .content = @embedFile(template_dir ++ "/site/pages/page+wasm.zx") },
    .{ .name = .wasm, .path = "site/pages/client.zx", .content = @embedFile(template_dir ++ "/site/pages/client.zx") },
    .{ .name = .wasm, .path = "package.json", .content = @embedFile(template_dir ++ "/package.json") },
    .{ .name = .wasm, .path = "tsconfig.json", .content = @embedFile(template_dir ++ "/tsconfig.json") },

    // React + WASM
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
