test "init" {
    if (!test_util.shouldRunSlowTest()) return error.SkipZigTest;
    try test_cmd(.{
        .args = &.{"init"},
        .expected_exit_code = 0,
        .expected_stderr_strings = &.{
            "Initializing ZX project!",
            "main.zig",
            ".gitattributes",
            "page.zx",
        },
        .expected_files = &.{
            "build.zig.zon",
            "build.zig",
            "site/main.zig",
            "site/pages/page.zx",
            "site/assets/style.css",
            "site/public/favicon.ico",
            "src/root.zig",
            ".gitignore",
            ".gitattributes",
            "README.md",
        },
    });
}

test "init → init" {
    if (!test_util.shouldRunSlowTest()) return error.SkipZigTest;
    try test_cmd(.{
        .args = &.{"init"},
        .expected_exit_code = 0,
        .expected_stderr_strings = &.{
            "Directory is not empty",
        },
    });
}

test "init --force" {
    if (!test_util.shouldRunSlowTest()) return error.SkipZigTest;
    try test_cmd(.{
        .args = &.{ "init", "--force" },
        .expected_exit_code = 0,
        .expected_stderr_strings = &.{
            "Initializing ZX project!",
            "main.zig",
            "page.zx",
        },
        .expected_files = &.{
            "build.zig.zon",
            "build.zig",
            "site/main.zig",
            "site/pages/page.zx",
            ".gitignore",
            ".gitattributes",
            "README.md",
        },
    });
}

test "init -t react" {
    if (!test_util.shouldRunSlowTest()) return error.SkipZigTest;
    try test_cmd(.{
        .args = &.{ "init", "react", "--template", "react" },
        .expected_exit_code = 0,
        .expected_stderr_strings = &.{
            "Initializing ZX project!",
            "react",
            "build.zig",
            "main.zig",
            "main.ts",
            "page.zx",
            "client.tsx",
            "package.json",
            ".gitattributes",
            "tsconfig.json",
        },
        .expected_files = &.{
            "react/build.zig.zon",
            "react/build.zig",
            "react/site/main.zig",
            "react/site/main.ts",
            "react/site/pages/page.zx",
            "react/site/pages/client.tsx",
            "react/package.json",
            "react/.gitattributes",
            "react/tsconfig.json",
        },
    });
}

test "init -t wasm" {
    if (!test_util.shouldRunSlowTest()) return error.SkipZigTest;
    try test_cmd(.{
        .args = &.{ "init", "wasm", "--template", "wasm" },
        .expected_exit_code = 0,
        .expected_stderr_strings = &.{
            "Initializing ZX project!",
            "wasm",
            "build.zig",
            "main.zig",
            "page.zx",
            ".gitattributes",
            "client.zx",
        },
        .expected_files = &.{
            "wasm/build.zig.zon",
            "wasm/build.zig",
            "wasm/site/main.zig",
            "wasm/site/pages/page.zx",
            "wasm/site/pages/client.zx",
        },
    });
}

// test "serve" {
//     if (!sholdRunSlowTest()) return error.SkipZigTest; // Slow test, will enable later, and execute as another steps as e2e before release
//     if (true) return error.Todo;

//     const zx_bin_abs = try getZxPath();
//     const test_dir_abs = try getTestDirPath();
//     defer allocator.free(zx_bin_abs);
//     defer allocator.free(test_dir_abs);

//     const port = "3456";
//     const port_colon = try std.fmt.allocPrint(allocator, ":{s}", .{port});
//     defer allocator.free(port_colon);

//     // Kill anything on that port (cross-platform)
//     killPort(port) catch {};

//     var build_child = std.process.Child.init(&.{ "zig", "build" }, allocator);
//     build_child.cwd = test_dir_abs;
//     build_child.stdout_behavior = .Ignore;
//     build_child.stderr_behavior = .Ignore;
//     try build_child.spawn();
//     _ = build_child.wait() catch {};

//     var child = std.process.Child.init(&.{ zx_bin_abs, "serve", "--port", port }, allocator);
//     child.cwd = test_dir_abs;
//     // child.stdout_behavior = .Ignore;
//     // child.stderr_behavior = .Ignore;
//     try child.spawn();
//     defer _ = child.kill() catch {};
//     errdefer _ = child.kill() catch {};

//     var client = std.http.Client{ .allocator = allocator };
//     defer client.deinit();

//     var aw = std.Io.Writer.Allocating.init(allocator);
//     defer aw.deinit();

//     const url = try std.fmt.allocPrint(allocator, "http://{s}:{s}", .{ "localhost", port });
//     defer allocator.free(url);

//     // wait for 2 seconds
//     std.Thread.sleep(std.time.ns_per_s * 1);
//     const result = try client.fetch(.{
//         .method = .GET,
//         .location = .{ .url = url },
//         .headers = std.http.Client.Request.Headers{},
//         .response_writer = &aw.writer,
//     });

//     // Wait 500ms
//     std.Thread.sleep(std.time.ns_per_ms * 500);
//     _ = child.kill() catch {};
//     errdefer _ = child.kill() catch {};

//     try std.testing.expectEqual(result.status, std.http.Status.ok);
// }

test "init → build" {
    if (!test_util.shouldRunSlowTest()) return error.SkipZigTest;

    const test_dir_abs = try getTestDirPath();
    defer allocator.free(test_dir_abs);

    // Update build.zig.zon to use the local zx dependency, copy local_zon_str to build.zig.zon
    const build_zig_zon_path = try std.fs.path.join(allocator, &.{ test_dir_abs, "build.zig.zon" });
    defer allocator.free(build_zig_zon_path);
    var build_zig_zon = try std.fs.openDirAbsolute(test_dir_abs, .{});
    defer build_zig_zon.close();
    try build_zig_zon.writeFile(.{ .sub_path = build_zig_zon_path, .data = local_zon_str });

    var build_child = std.process.Child.init(&.{ "zig", "build" }, allocator);
    build_child.cwd = test_dir_abs;
    // build_child.stdout_behavior = .Ignore;
    // build_child.stderr_behavior = .Ignore;
    try build_child.spawn();
    const exit_code = try build_child.wait();
    switch (exit_code) {
        .Exited => |code| try std.testing.expectEqual(code, 0),
        else => try std.testing.expect(false),
    }
}

test "init → build -t wasm" {
    if (!test_util.shouldRunSlowTest()) return error.SkipZigTest;

    const test_dir_abs = try getTestDirPath();
    defer allocator.free(test_dir_abs);

    // Update build.zig.zon to use the local zx dependency, copy local_zon_str to build.zig.zon
    const build_zig_zon_path = try std.fs.path.join(allocator, &.{ test_dir_abs, "wasm", "build.zig.zon" });
    defer allocator.free(build_zig_zon_path);
    var build_zig_zon = try std.fs.openDirAbsolute(test_dir_abs, .{});
    defer build_zig_zon.close();

    var aw = std.io.Writer.Allocating.init(allocator);
    defer aw.deinit();
    try std.zon.stringify.serialize(local_wasm_zon_str, .{ .whitespace = true }, &aw.writer);
    try build_zig_zon.writeFile(.{ .sub_path = build_zig_zon_path, .data = aw.written() });

    const wasm_path = try std.fs.path.join(allocator, &.{ test_dir_abs, "wasm" });
    defer allocator.free(wasm_path);
    var build_child = std.process.Child.init(&.{ "zig", "build" }, allocator);
    build_child.cwd = wasm_path;
    // build_child.stdout_behavior = .Ignore;
    // build_child.stderr_behavior = .Ignore;
    try build_child.spawn();
    const exit_code = try build_child.wait();
    switch (exit_code) {
        .Exited => |code| try std.testing.expectEqual(code, 0),
        else => try std.testing.expect(false),
    }
}

test "export" {
    if (!test_util.shouldRunSlowTest()) return error.SkipZigTest; // Export doesn't work on Windows yet
    killPort("3000") catch {};
    try test_cmd(.{
        .args = &.{"export"},
        .expected_exit_code = 0,
        .expected_stderr_strings = &.{
            "Building static ZX site!",
            "dist",
            "index.html",
            "about.html",
            "assets" ++ std.fs.path.sep_str ++ "style.css",
            "favicon.ico",
        },
        .expected_files = &.{
            "dist/index.html",
            "dist/about.html",
            "dist/assets/style.css",
            "dist/favicon.ico",
        },
    });
}

test "bundle" {
    if (!test_util.shouldRunSlowTest()) return error.SkipZigTest;
    try test_cmd(.{
        .args = &.{"bundle"},
        .expected_exit_code = 0,
        .expected_stderr_strings = &.{
            "Bundling ZX site!",
            "bundle",
            "zx_site",
            "style.css",
            "favicon.ico",
        },
        .expected_files = &.{
            "bundle/zx_site" ++ (if (builtin.os.tag == .windows) ".exe" else ""),
            "bundle/assets/style.css",
            "bundle/public/favicon.ico",
        },
    });
}

test "bundle --docker" {
    if (!test_util.shouldRunSlowTest()) return error.SkipZigTest;
    try test_cmd(.{
        .args = &.{ "bundle", "--docker" },
        .expected_exit_code = 0,
        .expected_stderr_strings = &.{
            "Bundling ZX site!",
            "bundle",
            "Dockerfile",
            ".dockerignore",
        },
        .expected_files = &.{
            "bundle/Dockerfile",
            "bundle/.dockerignore",
        },
    });
}

test "bundle --docker-compose" {
    if (!test_util.shouldRunSlowTest()) return error.SkipZigTest;
    try test_cmd(.{
        .args = &.{ "bundle", "--docker-compose" },
        .expected_exit_code = 0,
        .expected_stderr_strings = &.{
            "Bundling ZX site!",
            "bundle",
            "Dockerfile",
            "compose.yml",
            ".dockerignore",
        },
        .expected_files = &.{
            "bundle/Dockerfile",
            "bundle/compose.yml",
            "bundle/.dockerignore",
        },
    });
}

test "fmt" {
    try test_cmd(.{
        .args = &.{ "fmt", "site" ++ std.fs.path.sep_str ++ "pages" },
        .expected_exit_code = 0,
        .expected_stdout_strings = &.{
            // "site" ++ std.fs.path.sep_str ++ "pages" ++ std.fs.path.sep_str ++ "layout.zx",
            // "site" ++ std.fs.path.sep_str ++ "pages" ++ std.fs.path.sep_str ++ "page.zx",
        },
    });
}

test "upgrade" {
    // if (!test_util.shouldRunSlowTest()) return error.SkipZigTest;
    try test_cmd(.{
        .args = &.{"upgrade"},
        .expected_exit_code = 0,
        .expected_stdout_strings = &.{
            "was installed successfully",
            "0.1.0-dev",
        },
        .expected_files = &.{},
        .debug = true,
    });
}

const TestCmdOptions = struct {
    args: []const []const u8,
    expected_stderr_strings: []const []const u8 = &.{},
    expected_stdout_strings: []const []const u8 = &.{},
    expected_exit_code: i32 = 0,
    expected_files: []const []const u8 = &.{},
    debug: bool = false,
};
fn test_cmd(options: TestCmdOptions) !void {
    const zx_bin_abs = try getZxPath();
    const test_dir_abs = try getTestDirPath();
    defer allocator.free(zx_bin_abs);
    defer allocator.free(test_dir_abs);

    // Delete bundle or dist directory if it exists
    var test_dir = try std.fs.openDirAbsolute(test_dir_abs, .{});
    defer test_dir.close();
    test_dir.deleteTree("bundle") catch {};
    test_dir.deleteTree("dist") catch {};

    var args = std.ArrayList([]const u8).empty;
    defer args.deinit(allocator);
    try args.appendSlice(allocator, &.{zx_bin_abs});
    try args.appendSlice(allocator, options.args);

    var child = std.process.Child.init(args.items, allocator);
    child.cwd = test_dir_abs;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();

    var stdout = std.ArrayList(u8).empty;
    var stderr = std.ArrayList(u8).empty;
    defer stdout.deinit(allocator);
    defer stderr.deinit(allocator);
    try child.collectOutput(allocator, &stdout, &stderr, 8192);

    if (options.debug) {
        std.debug.print("\nstdout: {s}", .{stdout.items});
        std.debug.print("\nstderr: {s}", .{stderr.items});
    }

    for (options.expected_stderr_strings) |expected_string| {
        try std.testing.expect(std.mem.indexOf(u8, stderr.items, expected_string) != null);
    }
    for (options.expected_stdout_strings) |expected_string| {
        try std.testing.expect(std.mem.indexOf(u8, stdout.items, expected_string) != null);
    }
    const exit_code = try child.wait();
    switch (exit_code) {
        .Exited => |code| try std.testing.expectEqual(code, options.expected_exit_code),
        else => try std.testing.expect(false),
    }

    for (options.expected_files) |expected_file| {
        var expected_file_path = std.ArrayList([]const u8).empty;
        defer expected_file_path.deinit(allocator);
        try expected_file_path.appendSlice(allocator, &.{test_dir_abs});

        var path_iter = std.mem.splitSequence(u8, expected_file, "/");
        while (path_iter.next()) |part| {
            if (part.len > 0) {
                try expected_file_path.append(allocator, part);
            }
        }
        const expected_file_path_str = try std.fs.path.join(allocator, expected_file_path.items);
        defer allocator.free(expected_file_path_str);

        const file_stat = try std.fs.cwd().statFile(expected_file_path_str);
        try std.testing.expectEqual(file_stat.kind, .file);
    }
}

const local_zon_str =
    \\.{
    \\    .name = .zx_site,
    \\    .version = "0.0.0",
    \\    .fingerprint = 0xc04151551dc3c31d,
    \\    .minimum_zig_version = "0.15.2",
    \\    .dependencies = .{
    \\        .zx = .{
    \\            .path = "../../",
    \\        },
    \\    },
    \\    .paths = .{
    \\        "build.zig",
    \\        "build.zig.zon",
    \\        "src",
    \\    },
    \\}
;

var local_wasm_zon_str = .{
    .name = .zx_site,
    .version = "0.0.0",
    .fingerprint = 0xc04151551dc3c31d,
    .minimum_zig_version = "0.15.2",
    .dependencies = .{
        .zx = .{
            .path = "../../../",
        },
    },
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
    },
};

test "tests:beforeAll" {
    std.fs.cwd().deleteTree("test/tmp") catch {};
    std.fs.cwd().makeDir("test/tmp") catch {};
}

test "tests:afterAll" {
    // std.fs.cwd().deleteTree("test/tmp") catch {};
}

fn getZxPath() ![]const u8 {
    const zx_bin_rel = if (builtin.os.tag == .windows) "zig-out/bin/zx.exe" else "zig-out/bin/zx";
    const zx_bin_abs = try std.fs.cwd().realpathAlloc(allocator, zx_bin_rel);
    return zx_bin_abs;
}

fn getTestDirPath() ![]const u8 {
    const test_dir = "test/tmp";
    const test_dir_abs = try std.fs.cwd().realpathAlloc(allocator, test_dir);
    return test_dir_abs;
}

fn killPort(port: []const u8) !void {
    const target_os = builtin.target.os.tag;

    if (target_os == .windows) {
        // Windows: Use PowerShell to find and kill process on port
        const ps_command = try std.fmt.allocPrint(
            allocator,
            "Get-NetTCPConnection -LocalPort {s} -ErrorAction SilentlyContinue | ForEach-Object {{ Stop-Process -Id $_.OwningProcess -Force }}",
            .{port},
        );
        defer allocator.free(ps_command);

        var kill_child = std.process.Child.init(&.{ "powershell", "-Command", ps_command }, allocator);
        kill_child.stdout_behavior = .Pipe;
        kill_child.stderr_behavior = .Pipe;
        _ = kill_child.spawn() catch return;
        _ = kill_child.wait() catch {};
    } else {
        // Unix-like: Use lsof and kill
        const kill_command = try std.fmt.allocPrint(allocator, "kill -9 $(lsof -t -i:{s})", .{port});
        defer allocator.free(kill_command);

        var kill_child = std.process.Child.init(&.{ "sh", "-c", kill_command }, allocator);
        kill_child.stdout_behavior = .Pipe;
        kill_child.stderr_behavior = .Pipe;
        _ = kill_child.spawn() catch return;
        _ = kill_child.wait() catch {};
    }
}

const allocator = std.testing.allocator;
const test_util = @import("./../test_util.zig");

const std = @import("std");
const zx = @import("zx");
const builtin = @import("builtin");
