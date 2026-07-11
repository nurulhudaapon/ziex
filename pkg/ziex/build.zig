const std = @import("std");
const esbuild = @import("esbuild");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const is_release = optimize != .Debug;

    // --- JS bundles (esbuild) --- //
    const packages = esbuild.addBuild(b, .{
        .name = "ziex",
        .config = .{
            .entrypoints = &.{
                b.path("src/index.ts"),
                b.path("src/react/index.ts"),
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

    b.getInstallStep().dependOn(&b.addInstallDirectory(.{
        .source_dir = packages.dir,
        .install_dir = .prefix,
        .install_subdir = "",
    }).step);
    b.getInstallStep().dependOn(&b.addInstallFile(
        wasm_init.dir.path(b, "init.js"),
        "wasm/init.js",
    ).step);
    b.getInstallStep().dependOn(&b.addInstallFile(
        wasm_init_dev.dir.path(b, "init.js"),
        "wasm/init.dev.js",
    ).step);

    // --- TypeScript declarations --- //
    const tsc = b.addSystemCommand(&.{
        "node_modules/.bin/tsc",
        "--outDir",
    });
    tsc.setCwd(b.path(""));
    tsc.has_side_effects = true;
    const dts_dir = tsc.addOutputDirectoryArg("dts");
    tsc.addFileInput(b.path("tsconfig.emit.json"));

    b.getInstallStep().dependOn(&b.addInstallDirectory(.{
        .source_dir = dts_dir.path(b, "pkg/ziex/src"),
        .install_dir = .prefix,
        .install_subdir = "",
    }).step);

    // --- package.json for npm publish --- //
    b.getInstallStep().dependOn(&b.addInstallFile(try makePublishPackageJson(b), "package.json").step);

    // --- Static package files --- //
    b.getInstallStep().dependOn(&b.addInstallFile(b.path("../../README.md"), "README.md").step);
    b.getInstallStep().dependOn(&b.addInstallFile(b.path("bin/ziex"), "bin/ziex").step);
    b.getInstallStep().dependOn(&b.addInstallFile(b.path("build.zig"), "build.zig").step);
    b.getInstallStep().dependOn(&b.addInstallFile(b.path("build.zig.zon"), "build.zig.zon").step);
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
