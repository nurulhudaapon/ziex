const std = @import("std");
const esbuild = @import("esbuild");
const build_zon = @import("build.zig.zon");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    _ = target;
    const type_decl = b.option(bool, "type-decl", "Generate type declarations") orelse true;
    const is_release = optimize != .Debug;

    // --- JS bundles (esbuild) --- //
    const packages = esbuild.addBuild(b, .{
        .name = "ziex",
        .config = .{
            .entrypoints = &.{
                b.path("src/index.ts"),
                b.path("src/jsx/index.ts"),
                b.path("src/wasm/index.ts"),
                b.path("src/cloudflare/index.ts"),
                b.path("src/aws-lambda/index.ts"),
                b.path("src/vercel/index.ts"),
            },
            .format = .esm,
            .platform = .neutral,
            .minify = is_release,
            .define = &.{
                .{ .key = "__DEV__", .value = if (is_release) "false" else "true" },
            },
        },
    });

    const wasm_init = esbuild.addBuild(b, .{
        .name = "wasm_init",
        .config = .{
            .entrypoints = &.{b.path("src/wasm/init.ts")},
            .format = .esm,
            .platform = .browser,
            .minify = true,
            .define = &.{
                .{ .key = "__DEV__", .value = "false" },
            },
        },
    });

    const wasm_init_dev = esbuild.addBuild(b, .{
        .name = "wasm_init_dev",
        .config = .{
            .entrypoints = &.{b.path("src/wasm/init.ts")},
            .format = .esm,
            .platform = .browser,
            .minify = false,
            .define = &.{
                .{ .key = "__DEV__", .value = "true" },
            },
        },
    });

    const dist_files = b.addNamedWriteFiles("ziex_js");

    // --- App init files --- //
    {
        _ = dist_files.addCopyFile(wasm_init.dir.path(b, "init.js"), "wasm/init.js");
        _ = dist_files.addCopyFile(wasm_init_dev.dir.path(b, "init.js"), "wasm/init.dev.js");
    }

    // --- Static package files --- //
    {
        _ = dist_files.addCopyFile(try makePublishPackageJson(b), "package.json");
        _ = dist_files.addCopyFile(b.path("../../README.md"), "README.md");
        _ = dist_files.addCopyFile(b.path("bin/ziex"), "bin/ziex");
        _ = dist_files.addCopyFile(makePublishBuildZig(b), "build.zig");
        _ = dist_files.addCopyFile(try makePublishBuildZigZon(b), "build.zig.zon");

        // --- Other bindings --- //
        _ = dist_files.addCopyDirectory(packages.dir, "", .{});
    }

    // --- TypeScript declarations --- //
    if (type_decl) {
        const typescript = @import("typescript");
        const dts = typescript.addBuild(b, .{
            .name = "ziex.d.ts",
            .config = .{
                .project = b.path("tsconfig.json"),
            },
        });
        _ = dist_files.addCopyDirectory(dts.dir.path(b, "pkg/ziex/src"), "", .{});
    }

    b.getInstallStep().dependOn(&b.addInstallDirectory(.{
        .source_dir = dist_files.getDirectory(),
        .install_dir = .prefix,
        .install_subdir = "",
    }).step);
}

fn makePublishBuildZig(b: *std.Build) std.Build.LazyPath {
    return b.addWriteFiles().add(
        "build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    _ = b; // stub
        \\}
        \\
        ,
    );
}

fn makePublishBuildZigZon(b: *std.Build) !std.Build.LazyPath {
    // Re-serialize the package manifest without `.dependencies` (build-only plugins).
    const publish = .{
        .name = build_zon.name,
        .fingerprint = build_zon.fingerprint,
        .version = build_zon.version,
        .minimum_zig_version = build_zon.minimum_zig_version,
        .paths = build_zon.paths,
    };

    var aw: std.Io.Writer.Allocating = .init(b.allocator);
    defer aw.deinit();
    try std.zon.stringify.serialize(publish, .{ .whitespace = true }, &aw.writer);
    try aw.writer.writeByte('\n');

    const out = try b.allocator.dupe(u8, aw.written());
    defer b.allocator.free(out);
    return b.addWriteFiles().add("build.zig.zon", out);
}

fn makePublishPackageJson(b: *std.Build) !std.Build.LazyPath {
    const src = try b.root.root_dir.handle.readFileAlloc(b.graph.io, "package.json", b.allocator, .unlimited);
    defer b.allocator.free(src);

    var parsed = try std.json.parseFromSlice(std.json.Value, b.allocator, src, .{});
    defer parsed.deinit();

    const obj = &parsed.value.object;
    try obj.put(b.allocator, "main", .{ .string = "index.js" });
    try obj.put(b.allocator, "module", .{ .string = "index.js" });
    try obj.put(b.allocator, "types", .{ .string = "index.d.ts" });
    try obj.put(b.allocator, "scripts", .{ .object = .empty });
    _ = obj.swapRemove("private");
    _ = obj.swapRemove("devDependencies");
    _ = obj.swapRemove("peerDependencies");
    _ = obj.swapRemove("release");
    _ = obj.swapRemove("prettier");

    const json = try std.json.Stringify.valueAlloc(b.allocator, parsed.value, .{ .whitespace = .indent_2 });
    defer b.allocator.free(json);
    const out = try std.mem.concat(b.allocator, u8, &.{ json, "\n" });
    defer b.allocator.free(out);

    return b.addWriteFiles().add("package.json", out);
}
