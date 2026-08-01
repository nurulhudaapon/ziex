const std = @import("std");
const esbuild = @import("esbuild");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const is_release = optimize != .debug;

    // Pre-release is the default for pack/publish; use `-Dpre-release=false` for a stable VSIX.
    const pre_release = b.option(bool, "pre-release", "Mark the VSIX as a pre-release") orelse true;

    // --- Bundle extension (plugin-esbuild) --- //
    const bundled = esbuild.addBuild(b, .{
        .name = "extension",
        .config = .{
            .entrypoints = &.{b.path("src/extension.ts")},
            .platform = .node,
            .format = .cjs,
            .bundle = true,
            .minify = is_release,
            .sourcemap = if (is_release) .none else .@"inline",
            .external = &.{"vscode"},
        },
    });
    const extension_js = bundled.dir.path(b, "extension.js");

    // --- Branding (shared logo assets) --- //
    const branding = b.dependency("branding", .{});
    const branding_files = [_]struct { src: []const u8, dest: []const u8 }{
        .{ .src = "compressed/ziex-logo-colored-128x128.png", .dest = "images/ziex-logo-colored.png" },
        .{ .src = "ziex-logo-colored.svg", .dest = "images/ziex-logo-colored.svg" },
        // Language file icons: white on dark UI, black on light UI (transparent bg).
        .{ .src = "ziex-logo-white.svg", .dest = "images/ziex-logo-white.svg" },
        .{ .src = "ziex-logo-black.svg", .dest = "images/ziex-logo-black.svg" },
    };

    // Install bundled JS + branding into the prefix (zig-out by default, or `-p .`).
    b.getInstallStep().dependOn(&b.addInstallFile(extension_js, "out/extension.js").step);

    // Sync into the package tree so F5 / vsce see `out/` and `images/` next to package.json.
    const mkdir_out = b.addSystemCommand(&.{ "mkdir", "-p", "out" });
    mkdir_out.setCwd(b.path("."));
    mkdir_out.has_side_effects = true;
    const sync_js = syncFile(b, extension_js, "out/extension.js");
    sync_js.step.dependOn(&mkdir_out.step);
    b.getInstallStep().dependOn(&sync_js.step);

    for (branding_files) |file| {
        const src = branding.path(file.src);
        b.getInstallStep().dependOn(&b.addInstallFile(src, file.dest).step);
        b.getInstallStep().dependOn(&syncFile(b, src, file.dest).step);
    }

    // --- Pack (.vsix via local vsce) --- //
    const pack_cmd = addVsce(b, .pack, pre_release, "none");
    pack_cmd.step.dependOn(b.getInstallStep());
    const pack_step = b.step("pack", "Package the VS Code extension as a .vsix (pre-release by default)");
    pack_step.dependOn(&pack_cmd.step);

    // Always packs with --pre-release, regardless of -Dpre-release.
    const pre_release_cmd = addVsce(b, .pack, true, "none");
    pre_release_cmd.step.dependOn(b.getInstallStep());
    const pre_release_step = b.step("pre-release", "Package a pre-release .vsix");
    pre_release_step.dependOn(&pre_release_cmd.step);

    // --- Publish (marketplace via local vsce) --- //
    const bump = b.option([]const u8, "bump", "Semver bump for publish: patch, minor, major, or none") orelse "patch";
    const publish_cmd = addVsce(b, .publish, pre_release, bump);
    publish_cmd.step.dependOn(b.getInstallStep());
    const publish_step = b.step("publish", "Publish to the VS Code Marketplace (pre-release + patch bump by default)");
    publish_step.dependOn(&publish_cmd.step);
}

const VsceAction = enum { pack, publish };

fn addVsce(b: *std.Build, action: VsceAction, pre_release: bool, bump: []const u8) *std.Build.Step.Run {
    const cmd = b.addSystemCommand(&.{"node_modules/.bin/vsce"});
    cmd.addArg(@tagName(action));
    if (action == .publish) {
        cmd.addArg("--skip-duplicate");
        if (!std.mem.eql(u8, bump, "none")) {
            cmd.addArg(bump);
            cmd.addArg("--no-git-tag-version");
        }
    }
    if (pre_release) cmd.addArg("--pre-release");
    cmd.setCwd(b.path("."));
    cmd.has_side_effects = true;
    return cmd;
}

fn syncFile(b: *std.Build, src: std.Build.LazyPath, dest_rel: []const u8) *std.Build.Step.Run {
    const cp = b.addSystemCommand(&.{"cp"});
    cp.addFileArg(src);
    cp.addArg(dest_rel);
    cp.setCwd(b.path("."));
    cp.has_side_effects = true;
    return cp;
}
