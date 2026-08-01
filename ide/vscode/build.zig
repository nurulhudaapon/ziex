const std = @import("std");
const esbuild = @import("esbuild");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const is_release = optimize != .debug;
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
        .{ .src = "compressed/ziex-logo-black-liquid-glass-128x128.png", .dest = "images/logo.png" },
        .{ .src = "ziex-logo-colored.svg", .dest = "images/icon.svg" },
    };
    const pkg_root: std.Build.InstallDir = .{ .custom = ".." };

    b.getInstallStep().dependOn(&b.addInstallFile(extension_js, "out/extension.js").step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(extension_js, pkg_root, "out/extension.js").step);

    for (branding_files) |file| {
        const src = branding.path(file.src);
        b.getInstallStep().dependOn(&b.addInstallFile(src, file.dest).step);
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(src, pkg_root, file.dest).step);
    }

    // --- Pack (.vsix via npx @vscode/vsce) --- //
    const pack_cmd = addVsce(b, .pack, pre_release, null);
    pack_cmd.step.dependOn(b.getInstallStep());
    const pack_step = b.step("pack", "Package the VS Code extension as a .vsix (pre-release by default)");
    pack_step.dependOn(&pack_cmd.step);

    const pre_release_cmd = addVsce(b, .pack, true, null);
    pre_release_cmd.step.dependOn(b.getInstallStep());
    const pre_release_step = b.step("pre-release", "Package a pre-release .vsix");
    pre_release_step.dependOn(&pre_release_cmd.step);

    // --- Publish (marketplace via npx @vscode/vsce) --- //
    const version = b.option([]const u8, "version", "Extension version to publish (e.g. 0.1.1234)");
    const publish_cmd = addVsce(b, .publish, pre_release, version);
    publish_cmd.step.dependOn(b.getInstallStep());
    const publish_step = b.step("publish", "Publish to the VS Code Marketplace (pre-release by default)");
    publish_step.dependOn(&publish_cmd.step);
}

const VsceAction = enum { pack, publish };

fn addVsce(b: *std.Build, action: VsceAction, pre_release: bool, version: ?[]const u8) *std.Build.Step.Run {
    const cmd = b.addSystemCommand(&.{ "npx", "--yes", "@vscode/vsce" });
    cmd.addArg(@tagName(action));
    if (action == .publish) {
        cmd.addArg("--skip-duplicate");
        if (version) |v| {
            cmd.addArg(v);
            cmd.addArg("--no-git-tag-version");
        }
    }
    if (pre_release) cmd.addArg("--pre-release");
    cmd.setCwd(b.path("."));
    cmd.has_side_effects = true;
    return cmd;
}
