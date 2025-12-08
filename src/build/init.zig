const std = @import("std");

/// Options for initializing a ZX project
pub const ZxInitOptions = struct {
    const CliOptions = struct {
        const Steps = struct {
            serve: []const u8 = "serve",
            dev: ?[]const u8 = null,
            @"export": ?[]const u8 = null,
            bundle: ?[]const u8 = null,
        };
        /// Path to the ZX CLI executable, if null then the ZX CLI will be used from source of ZX dependency
        /// If you want to use the ZX CLI from the system path, you can set the path to `zx`
        path: ?[]const u8 = null,

        steps: ?Steps = .{
            .serve = "serve",
        },
    };

    const SiteOptions = struct {
        /// Path to the ZX site, by default it is `site`
        path: []const u8,
    };

    const ExperimentalOptions = struct {
        /// Enabled Client Side Rendering (CSR)
        enabled_csr: bool = false,
    };

    // It is recommended to use the default options, but you can override them if you want to
    site: ?SiteOptions = null,

    /// Options for the ZX CLI
    cli: ?CliOptions = null,

    /// Experimental options, if null then the experimental options will be used from the source of ZX dependency
    experimental: ?ExperimentalOptions = null,
};

const default_inner_opts: InitInnerOptions = .{
    .site_path = "site",
    .cli_path = null,
    .site_outdir = null,
    .steps = .{
        .serve = "serve",
    },
};

pub fn init(b: *std.Build, exe: *std.Build.Step.Compile, options: ZxInitOptions) !void {
    const target = exe.root_module.resolved_target;
    const optimize = exe.root_module.optimize;
    const build_zig = @import("../../build.zig");
    const zx_dep = b.dependencyFromBuildZig(build_zig, .{ .target = target, .optimize = optimize });

    const zx_module = zx_dep.module("zx");
    const zx_wasm_module = zx_dep.module("zx_wasm");
    const zx_exe = zx_dep.artifact("zx");

    var opts = default_inner_opts;

    if (options.site) |site_opts| {
        opts.site_path = site_opts.path;
    }

    if (options.cli) |cli_opts| {
        opts.cli_path = cli_opts.path;
    }

    if (options.experimental) |experimental_opts| {
        opts.experimental_enabled_csr = experimental_opts.enabled_csr;
    }

    if (options.cli) |cli_opts| {
        if (cli_opts.steps) |cli_steps| {
            opts.steps = cli_steps;
        }
    }

    return initInner(b, exe, zx_exe, zx_module, zx_wasm_module, opts);
}

const InitInnerOptions = struct {
    site_path: []const u8,
    cli_path: ?[]const u8,
    site_outdir: ?[]const u8 = null,
    steps: ZxInitOptions.CliOptions.Steps = .{
        .serve = "serve",
    },

    experimental_enabled_csr: bool = false,
};

fn getZxRun(b: *std.Build, zx_exe: *std.Build.Step.Compile, opts: InitInnerOptions) *std.Build.Step.Run {
    const transpile_cmd = transpile_blk: {
        if (opts.cli_path != null) break :transpile_blk b.addSystemCommand(&.{opts.cli_path.?});
        break :transpile_blk b.addRunArtifact(zx_exe);
    };
    return transpile_cmd;
}
fn getTranspileOutdir(b: *std.Build, transpile_cmd: *std.Build.Step.Run, opts: InitInnerOptions) std.Build.LazyPath {
    return outdir_blk: {
        if (opts.site_outdir != null) {
            transpile_cmd.addArg(opts.site_outdir.?);
            break :outdir_blk b.path(opts.site_outdir.?);
        } else {
            break :outdir_blk transpile_cmd.addOutputDirectoryArg(opts.site_path);
        }
    };
}
pub fn initInner(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    zx_exe: *std.Build.Step.Compile,
    zx_module: *std.Build.Module,
    zx_wasm_module: *std.Build.Module,
    opts: InitInnerOptions,
) !void {
    // const target = exe.root_module.resolved_target;
    const optimize = exe.root_module.optimize;

    // --- ZX Transpilation ---
    const transpile_cmd = getZxRun(b, zx_exe, opts);
    transpile_cmd.addArgs(&.{ "transpile", b.pathJoin(&.{opts.site_path}), "--outdir" });
    const transpile_outdir = getTranspileOutdir(b, transpile_cmd, opts);
    transpile_cmd.expectExitCode(0);

    // --- ZX File Cache Invalidator ---
    const site_path = b.path(opts.site_path).getPath3(b, &transpile_cmd.step);
    var site_dir = try site_path.root_dir.handle.openDir(site_path.subPathOrDot(), .{ .iterate = true });
    var itd = try site_dir.walk(transpile_cmd.step.owner.allocator);
    defer itd.deinit();
    while (try itd.next()) |entry| {
        switch (entry.kind) {
            .directory => {},
            .file => {
                const entry_path = try site_path.join(transpile_cmd.step.owner.allocator, entry.path);
                transpile_cmd.addFileInput(b.path(entry_path.sub_path));
            },
            else => continue,
        }
    }

    // --- ZX Site Main Executable --- //
    exe.root_module.addImport("zx", zx_module);

    var imports = std.array_list.Managed(std.Build.Module.Import).init(b.allocator);
    var import_it = exe.root_module.import_table.iterator();
    while (import_it.next()) |entry| {
        try imports.append(.{ .name = entry.key_ptr.*, .module = entry.value_ptr.* });
    }

    exe.root_module.addAnonymousImport("zx_meta", .{
        .root_source_file = transpile_outdir.path(b, "meta.zig"),
        .imports = imports.items,
    });

    exe.step.dependOn(&transpile_cmd.step);
    b.installArtifact(exe);

    // --- ZX WASM Main Executable --- //
    if (opts.experimental_enabled_csr) {
        const wasm_exe = b.addExecutable(.{
            .name = b.fmt("main", .{}),
            .root_module = b.createModule(.{
                .root_source_file = exe.root_module.root_source_file,
                .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding, .abi = .none }),
                .optimize = if (optimize == .ReleaseFast) .ReleaseSmall else optimize,
            }),
        });
        wasm_exe.entry = .disabled;
        wasm_exe.export_memory = true;
        wasm_exe.rdynamic = true;
        wasm_exe.root_module.addImport("zx", zx_wasm_module);
        wasm_exe.root_module.addAnonymousImport("zx_components", .{
            .root_source_file = transpile_outdir.path(b, "components.zig"),
            .imports = &.{.{ .name = "zx", .module = zx_wasm_module }},
        });
        wasm_exe.step.dependOn(&transpile_cmd.step);

        // --- CMD: ZX Post Transpile --- //
        const post_transpile_cmd = getZxRun(b, zx_exe, opts);
        post_transpile_cmd.addArgs(&.{"transpile"});
        post_transpile_cmd.addFileArg(wasm_exe.getEmittedBin());
        post_transpile_cmd.addArgs(&.{ "--copy-only", "--outdir" });
        post_transpile_cmd.addDirectoryArg(transpile_outdir.path(b, "assets"));
        post_transpile_cmd.expectExitCode(0);
        post_transpile_cmd.step.dependOn(&transpile_cmd.step);
        post_transpile_cmd.step.dependOn(&wasm_exe.step);
        b.default_step.dependOn(&post_transpile_cmd.step);
    }

    // --- Steps: Serve --- //
    {
        const serve_step = b.step("serve", "Run the Zx website");
        const serve_cmd = b.addRunArtifact(exe);
        serve_cmd.step.dependOn(b.getInstallStep());
        serve_cmd.step.dependOn(&transpile_cmd.step);
        serve_step.dependOn(&serve_cmd.step);
        if (b.args) |args| serve_cmd.addArgs(args);
    }

    // --- Steps: Dev --- //
    if (opts.steps.dev) |dev_step_name| {
        const dev_cmd = getZxRun(b, zx_exe, opts);
        dev_cmd.addArgs(&.{"dev"});
        const dev_step = b.step(dev_step_name, "Run the Zx website in development mode");
        dev_step.dependOn(&dev_cmd.step);
        if (b.args) |args| dev_cmd.addArgs(args);
    }

    // --- Steps: Export --- //
    if (opts.steps.@"export") |export_step_name| {
        const export_cmd = getZxRun(b, zx_exe, opts);
        export_cmd.addArgs(&.{"export"});
        const export_step = b.step(export_step_name, "Export the Zx website");
        export_step.dependOn(&export_cmd.step);
        if (b.args) |args| export_cmd.addArgs(args);
    }

    // --- Steps: Bundle --- //
    if (opts.steps.bundle) |bundle_step_name| {
        const bundle_cmd = getZxRun(b, zx_exe, opts);
        bundle_cmd.addArgs(&.{"bundle"});
        const bundle_step = b.step(bundle_step_name, "Bundle the Zx website");
        bundle_step.dependOn(&bundle_cmd.step);
        if (b.args) |args| bundle_cmd.addArgs(args);
    }
}
