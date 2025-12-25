const std = @import("std");
const LazyPath = std.Build.LazyPath;
pub const ZxInitOptions = @import("init/ZxInitOptions.zig");

pub fn init(b: *std.Build, exe: *std.Build.Step.Compile, options: ZxInitOptions) !void {
    const target = exe.root_module.resolved_target;
    const optimize = exe.root_module.optimize;
    const build_zig = @import("../../build.zig");
    const zx_dep = b.dependencyFromBuildZig(build_zig, .{ .target = target, .optimize = optimize });

    const zx_module = zx_dep.module("zx");
    const zx_wasm_module = zx_dep.module("zx_wasm");
    const zx_exe = zx_dep.artifact("zx");

    var opts: InitInnerOptions = .{
        .site_path = b.path("site"),
        .cli_path = null,
        .site_outdir = null,
        .steps = .default,
        .plugins = &.{},
        .experimental_enabled_csr = false,
    };

    if (options.site) |site_opts| {
        opts.site_path = site_opts.path;
    }

    if (options.cli) |cli_opts| {
        opts.cli_path = cli_opts.path;

        if (cli_opts.steps) |cli_steps| {
            opts.steps = cli_steps;
        }
    }

    if (options.experimental) |experimental_opts| {
        opts.experimental_enabled_csr = experimental_opts.enabled_csr;
    }

    if (options.plugins) |plugins| {
        opts.plugins = plugins;
    }

    return initInner(b, exe, zx_exe, zx_module, zx_wasm_module, opts);
}

const InitInnerOptions = struct {
    site_path: LazyPath,
    cli_path: ?LazyPath,
    site_outdir: ?LazyPath,
    steps: ZxInitOptions.CliOptions.Steps,
    plugins: []const ZxInitOptions.PluginOptions,
    experimental_enabled_csr: bool,
};

fn getZxRun(b: *std.Build, zx_exe: *std.Build.Step.Compile, opts: InitInnerOptions) *std.Build.Step.Run {
    if (opts.cli_path) |cli_path| {
        const run = b.addSystemCommand(&.{});
        run.addFileArg(cli_path);
        return run;
    }

    return b.addRunArtifact(zx_exe);
}

fn getTranspileOutdir(transpile_cmd: *std.Build.Step.Run, opts: InitInnerOptions) std.Build.LazyPath {
    if (opts.site_outdir) |site_outdir| {
        transpile_cmd.addDirectoryArg(site_outdir);
        return site_outdir;
    }

    // if user didn't provide a path, they don't want to keep transpiled output
    // this will put the transpiled output in .zig-cache/o/{HASH}/site
    return transpile_cmd.addOutputDirectoryArg("site");
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
    transpile_cmd.addArg("transpile");
    transpile_cmd.addDirectoryArg(opts.site_path);
    transpile_cmd.addArg("--outdir");
    const transpile_outdir = getTranspileOutdir(transpile_cmd, opts);
    transpile_cmd.expectExitCode(0);

    // --- ZX File Cache Invalidator ---
    const site_path = opts.site_path.getPath3(b, &transpile_cmd.step);
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
        const serve_step = b.step(opts.steps.serve, "Run the Zx website");
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

    // --- Plugins --- //
    for (opts.plugins) |*plugin| {
        for (plugin.steps) |*step| {
            switch (step.*) {
                .command => {
                    var run = step.command.run;
                    run.setName(plugin.name);

                    for (run.argv.items) |*arg| {
                        switch (arg.*) {
                            .lazy_path => |path| {
                                // if path starts with placeholder, replace with the actual location
                                const outdir_placeholder = "{outdir}";

                                const template = path.lazy_path.getPath3(b, null).sub_path;

                                if (std.mem.startsWith(u8, template, outdir_placeholder)) {
                                    const sub_path = if (outdir_placeholder.len == template.len)
                                        ""
                                    else
                                        template[outdir_placeholder.len + 1 ..];

                                    const replaced = transpile_outdir.path(b, sub_path);

                                    arg.* = .{
                                        .lazy_path = .{
                                            .prefix = path.prefix, // Preserve the original prefix (e.g. --outfile=)
                                            .lazy_path = replaced,
                                        },
                                    };
                                }
                            },
                            else => {},
                        }
                    }

                    switch (step.command.type) {
                        .before_transpile => transpile_cmd.step.dependOn(&run.step),
                        .after_transpile => {
                            run.step.dependOn(&transpile_cmd.step);
                            exe.step.dependOn(&run.step);
                        },
                    }
                },
            }
        }
    }
}
