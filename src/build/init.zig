const std = @import("std");
const injection = @import("init/injection.zig");

const LazyPath = std.Build.LazyPath;
const AddElementOptions = injection.AddElementOptions;
const InjectionsGenStep = injection.InjectionsGenStep;

pub const InitOptions = @import("init/InitOptions.zig");

pub fn init(b: *std.Build, exe: *std.Build.Step.Compile, options: InitOptions) !Build {
    const target = exe.root_module.resolved_target;
    const optimize = exe.root_module.optimize;
    const build_zig = @import("../../build.zig");
    const wasm_target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding, .abi = .none });

    const zx_dep = b.dependencyFromBuildZig(build_zig, .{
        .optimize = optimize,
        .target = target,
    });

    const zx_host_dep = b.dependencyFromBuildZig(build_zig, .{
        .optimize = options.cli.optimize, // Always in release mode for faster transpilation
        // No target = host target, so zx CLI can execute during build
        .@"exclude-lsp" = true, // Skip LSP for faster build-time transpilation
    });

    // Full CLI dep (includes LSP) for the `zig build zx` step
    const zx_full_dep = b.dependencyFromBuildZig(build_zig, .{
        .optimize = options.cli.optimize,
    });

    const zx_wasm_dep = b.dependencyFromBuildZig(build_zig, .{
        .optimize = optimize,
        .target = wasm_target,
    });

    const zx_module = zx_dep.module("zx");
    const zx_wasm_module = zx_wasm_dep.module("zx_wasm");
    const zx_exe = zx_host_dep.artifact("zx");
    const zx_full_exe = zx_full_dep.artifact("zx");
    const ziex_js_dep = zx_dep.builder.dependency("ziex_js", .{});

    var opts: InitInnerOptions = .{
        .site_path = b.path("app"),
        .cli_path = null,
        .site_outdir = null,
        .steps = .default,
        .copy_embedded_sources = false,
        .client = options.client,
        .static_path = options.static_path,
        .data_path = options.data_path,
        .ziex_js_dep = ziex_js_dep,
        .version = options.version,
    };

    if (options.app) |site_opts| {
        opts.site_path = site_opts.path;
        opts.copy_embedded_sources = site_opts.copy_embedded_sources;
    }

    opts.cli_path = options.cli.path;

    if (options.cli.steps) |cli_steps| {
        opts.steps = cli_steps;
    }

    return initInner(b, exe, zx_exe, zx_full_exe, zx_module, zx_wasm_module, opts);
}

const InitInnerOptions = struct {
    site_path: LazyPath,
    cli_path: ?LazyPath,
    site_outdir: ?LazyPath,
    steps: InitOptions.CliOptions.Steps,
    copy_embedded_sources: bool,
    client: InitOptions.ClientOptions,
    static_path: ?LazyPath,
    data_path: ?LazyPath,
    ziex_js_dep: *std.Build.Dependency,
    element_injections: []const AddElementOptions = &.{},
    version: ?[]const u8 = null,
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
    // this will put the transpiled output in .zig-cache/o/{HASH}/app
    return transpile_cmd.addOutputDirectoryArg("app");
}

pub fn initInner(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    zx_exe: *std.Build.Step.Compile,
    zx_full_exe: *std.Build.Step.Compile,
    zx_module: *std.Build.Module,
    zx_wasm_module: *std.Build.Module,
    opts: InitInnerOptions,
) !Build {
    // const target = exe.root_module.resolved_target;
    const optimize = exe.root_module.optimize;
    const build_zon = @import("../../build.zig.zon");

    // --- ZX Options --- //
    const zx_options = b.addOptions();
    zx_options.addOption(?[]const u8, "jsglue_href", opts.client.jsglue_href);
    zx_module.addOptions("zx_options", zx_options);

    // --- Dirs Setup --- //
    const static_lazypath: LazyPath = if (opts.static_path) |p| p else .{ .cwd_relative = b.pathJoin(&.{ b.install_path, "static" }) };
    const staticdir = static_lazypath.getPath(b);
    const assetsdir = static_lazypath.path(b, "assets");
    const datadir = if (opts.data_path) |p| p.getPath(b) else b.pathJoin(&.{ b.install_path, "data" });

    zx_options.addOption([]const u8, "staticdir", staticdir);
    zx_options.addOption([]const u8, "datadir", datadir);

    // --- ZX Transpilation ---
    const transpile_cmd = getZxRun(b, zx_exe, opts);
    transpile_cmd.setName("zx transpile");
    transpile_cmd.addArg("transpile");
    transpile_cmd.addDirectoryArg(opts.site_path);
    transpile_cmd.addArg("--outdir");
    const transpile_outdir = getTranspileOutdir(transpile_cmd, opts);
    transpile_cmd.addArg("--rootdir");
    transpile_cmd.addDirectoryArg(static_lazypath);
    transpile_cmd.addArg("--dep-file");
    _ = transpile_cmd.addDepFileOutputArg("transpile.d");
    if (opts.copy_embedded_sources) {
        transpile_cmd.addArg("--copy-embedded-sources");
    }
    // Always generate inlined sourcemaps so dev mode can remap errors to .zx files
    transpile_cmd.addArgs(&.{ "--map", "inline" });
    transpile_cmd.expectExitCode(0);

    const zxjs_default_href = "/assets/_/main.js";
    var zxjs_href = opts.client.jsglue_href orelse zxjs_default_href;
    // --- Static Directory Setup --- //
    {
        // Install public directory into static (only if the directory exists)
        const public_abs_path = opts.site_path.path(b, "public").getPath(b);
        if (std.fs.accessAbsolute(public_abs_path, .{})) |_| {
            const install_static = b.addInstallDirectory(.{
                .source_dir = opts.site_path.path(b, "public"),
                .install_dir = .prefix,
                .install_subdir = "static",
            });
            exe.step.dependOn(&install_static.step);
        } else |_| {}

        // Also install the generated assets into static/assets (only if the directory exists)
        const assets_abs_path = opts.site_path.path(b, "assets").getPath(b);
        if (std.fs.accessAbsolute(assets_abs_path, .{})) |_| {
            const install_assets = b.addInstallDirectory(.{
                .source_dir = opts.site_path.path(b, "assets"),
                .install_dir = .prefix,
                .install_subdir = "static/assets",
            });
            exe.step.dependOn(&install_assets.step);
        } else |_| {}

        var local_zxjs_path: ?LazyPath = opts.ziex_js_dep.path("wasm/init.js");

        if (opts.client.jsglue_href) |jsglue_href| {
            const is_remote = std.mem.startsWith(u8, jsglue_href, "http://") or std.mem.startsWith(u8, jsglue_href, "https://");
            if (is_remote) {
                local_zxjs_path = null;
                zxjs_href = jsglue_href;
            }
        }

        if (local_zxjs_path) |local_path| {
            // Install jsglue (wasm/init.js) from ziex_js package to static/assets/_/main.js
            const install_jsglue = b.addInstallFileWithDir(
                local_path,
                .prefix,
                "static" ++ zxjs_default_href,
            );
            exe.step.dependOn(&install_jsglue.step);
        }
    }

    // --- ZX Injections --- //
    const version = opts.version orelse build_zon.version;
    const injections_step = try InjectionsGenStep.create(b);
    for (opts.element_injections) |inj| {
        injections_step.add(inj);
    }
    // Inject wasm preload link tag into head
    injections_step.add(.{
        .parent = .head,
        .position = .ending,
        .element = .{
            .tag = "link",
            .attributes = b.fmt(
                "id=\"__$wasmlink\" rel=\"preload\" as=\"fetch\" href=\"/assets/_/main.wasm?{s}\" crossorigin",
                .{version},
            ),
        },
    });
    // Inject jsglue script tag via the build system
    injections_step.add(.{ .parent = .body, .position = .ending, .element = .{
        .tag = "script",
        .attributes = b.fmt("src=\"{s}?{s}\"", .{ zxjs_href, version }),
    } });
    zx_module.addAnonymousImport("zx_injections", .{
        .root_source_file = injections_step.getOutput(),
    });
    zx_wasm_module.addAnonymousImport("zx_injections", .{
        .root_source_file = injections_step.getOutput(),
    });

    // --- ZX File Cache Invalidator ---
    watch: {
        const site_path = opts.site_path.getPath3(b, &transpile_cmd.step);
        var site_dir = site_path.root_dir.handle.openDir(site_path.subPathOrDot(), .{ .iterate = true }) catch break :watch;
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
    }

    // --- ZX Site Main Executable --- //
    var imports = std.array_list.Managed(std.Build.Module.Import).init(b.allocator);
    var import_it = exe.root_module.import_table.iterator();
    while (import_it.next()) |entry| {
        try imports.append(.{ .name = entry.key_ptr.*, .module = entry.value_ptr.* });
    }

    // Copy all imports from the original zx_module
    var zx_import_it = zx_module.import_table.iterator();
    while (zx_import_it.next()) |entry| {
        if (!std.mem.eql(u8, entry.key_ptr.*, "zx_meta")) {
            try imports.append(.{ .name = entry.key_ptr.*, .module = entry.value_ptr.* });
        }
    }

    // Create a site-specific zx module with the generated meta
    const site_zx_module = b.createModule(.{
        .root_source_file = zx_module.root_source_file,
        .target = zx_module.resolved_target,
        .optimize = zx_module.optimize,
        .imports = imports.items,
    });

    // Build imports for zx_meta (needs access to zx module and all other imports)
    var meta_imports = std.array_list.Managed(std.Build.Module.Import).init(b.allocator);
    for (imports.items) |import| {
        try meta_imports.append(import);
    }
    try meta_imports.append(.{ .name = "zx", .module = site_zx_module });

    // Add project-specific zx_meta to the site module
    site_zx_module.addAnonymousImport("zx_meta", .{
        .root_source_file = transpile_outdir.path(b, "meta.zig"),
        .imports = meta_imports.items,
    });

    exe.root_module.addImport("zx", site_zx_module);

    exe.step.dependOn(&transpile_cmd.step);
    exe.step.name = b.fmt("install {s}server{s} {s}", .{ colors.dim, colors.reset, exe.name });
    b.installArtifact(exe);

    // --- ZX WASM Main Executable --- //
    const wasm_target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding, .abi = .none });
    const wasm_exe = b.addExecutable(.{
        .name = b.fmt("main", .{}),
        .root_module = b.createModule(.{
            .root_source_file = exe.root_module.root_source_file,
            .target = wasm_target,
            .optimize = optimize,
        }),
    });

    wasm_exe.entry = .disabled;
    wasm_exe.export_memory = true;
    wasm_exe.rdynamic = true;

    // Create a site-specific wasm module (same approach as server module)
    var wasm_imports = std.array_list.Managed(std.Build.Module.Import).init(b.allocator);
    var wasm_import_it = zx_wasm_module.import_table.iterator();
    while (wasm_import_it.next()) |entry| {
        if (!std.mem.eql(u8, entry.key_ptr.*, "zx_meta")) {
            try wasm_imports.append(.{ .name = entry.key_ptr.*, .module = entry.value_ptr.* });
        }
    }

    const site_wasm_module = b.createModule(.{
        .root_source_file = zx_wasm_module.root_source_file,
        .target = wasm_target,
        .optimize = zx_wasm_module.optimize,
        .imports = wasm_imports.items,
    });

    // Build imports for wasm zx_meta
    var wasm_meta_imports = std.array_list.Managed(std.Build.Module.Import).init(b.allocator);
    for (wasm_imports.items) |import| {
        try wasm_meta_imports.append(import);
    }
    try wasm_meta_imports.append(.{ .name = "zx", .module = site_wasm_module });

    const wasm_zx_meta_module = b.addModule("zx_meta", .{
        .root_source_file = transpile_outdir.path(b, "meta.zig"),
        .imports = wasm_meta_imports.items,
    });

    site_wasm_module.addImport("zx_meta", wasm_zx_meta_module);
    wasm_exe.root_module.addImport("zx", site_wasm_module);
    wasm_exe.step.dependOn(&transpile_cmd.step);

    const wasm_binpath = wasm_exe.getEmittedBin();
    const install_wasm = b.addInstallFileWithDir(
        wasm_binpath,
        .{ .custom = "static/assets/_" },
        "main.wasm",
    );

    install_wasm.step.name = b.fmt("install {s}client{s} {s}", .{ colors.dim, colors.reset, exe.name });

    b.default_step.dependOn(&install_wasm.step);

    // --- Steps: ZX (Root of ZX CLI) --- //
    {
        const zx_step = b.step(
            "zx",
            b.fmt("ZX CLI - \x1b[2m{s}\x1b[0m", .{"zig build zx -- <args>"}),
        );
        const zx_cmd = b.addRunArtifact(zx_full_exe);
        zx_step.dependOn(&zx_cmd.step);
        if (b.args) |args| zx_cmd.addArgs(args);
    }

    // --- Steps: Serve --- //
    if (opts.steps.serve) |serve_step_name| {
        const serve_step = b.step(serve_step_name, "Run the Ziex app with production behavior");
        const serve_cmd = b.addRunArtifact(exe);
        serve_cmd.step.dependOn(b.getInstallStep());
        serve_cmd.step.dependOn(&transpile_cmd.step);
        serve_step.dependOn(&serve_cmd.step);
        if (b.args) |args| serve_cmd.addArgs(args);
    }

    // --- Steps: Dev --- //
    if (opts.steps.dev) |dev_step_name| {
        const dev_cmd = getZxRun(b, zx_exe, opts);
        dev_cmd.addArgs(&.{
            "dev",
            // "--binpath",
        });
        // dev_cmd.addFileArg(exe.getEmittedBin());
        const dev_step = b.step(dev_step_name, "Run the Ziex app in development mode");
        dev_step.dependOn(&dev_cmd.step);
        if (b.args) |args| dev_cmd.addArgs(args);
    }

    // --- Steps: Export --- //
    if (opts.steps.@"export") |export_step_name| {
        const export_cmd = getZxRun(b, zx_exe, opts);
        export_cmd.addArgs(&.{"export"});
        const export_step = b.step(export_step_name, "Export the Ziex app for static hosting");
        export_step.dependOn(&export_cmd.step);
        if (b.args) |args| export_cmd.addArgs(args);
    }

    // --- Steps: Bundle --- //
    if (opts.steps.bundle) |bundle_step_name| {
        const bundle_cmd = getZxRun(b, zx_exe, opts);
        bundle_cmd.addArgs(&.{"bundle"});
        const bundle_step = b.step(bundle_step_name, "Bundle the Ziex app for production deployment");
        bundle_step.dependOn(&bundle_cmd.step);
        if (b.args) |args| bundle_cmd.addArgs(args);
    }

    return .{
        .build = b,
        .cmd = .{
            .transpile = transpile_cmd,
        },
        .outdir = transpile_outdir,
        .assetsdir = assetsdir,
        .zx = .{
            .exe = zx_exe,
        },
        .server = .{
            .exe = exe,
        },
        .client = .{
            .exe = wasm_exe,
            .root_module = wasm_zx_meta_module,
        },
        .injections_step = injections_step,
        .zx_build_options = zx_options,
        .ziex_js = .{
            .dep = opts.ziex_js_dep,
        },
    };
}

pub const Build = struct {
    pub const PluginRun = struct {};

    pub const BuildClient = struct {
        exe: *std.Build.Step.Compile,
        root_module: *std.Build.Module,
    };

    pub const BuildServer = struct {
        exe: *std.Build.Step.Compile,
    };

    pub const BuildZiex = struct {
        exe: *std.Build.Step.Compile,
    };

    pub const BuildZiexJs = struct {
        dep: *std.Build.Dependency,
    };

    pub const BuildCommand = struct {
        transpile: *std.Build.Step.Run,
    };

    build: *std.Build,

    cmd: BuildCommand,

    outdir: LazyPath,
    assetsdir: LazyPath,

    zx: BuildZiex,

    server: BuildServer,
    client: ?BuildClient,

    ziex_js: BuildZiexJs,

    /// Handle to the injections generator
    injections_step: *InjectionsGenStep,
    /// Handle to the build options module
    zx_build_options: *std.Build.Step.Options,

    pub fn addPlugin(self: *Build, opts: InitOptions.PluginOptions) *PluginRun {
        for (opts.steps) |*step| {
            switch (step.*) {
                .command => {
                    var run = step.command.run;

                    // TODO: Fails when used with remote package, was added to supress the output of TW Plugin
                    // But it tries to check for that before the plugin is run, so it fails.
                    // _ = run.captureStdErr();
                    // run.captured_stderr = null;
                    run.setName(opts.name);

                    const transpile_cmd = self.cmd.transpile;
                    const exe = self.server.exe;
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

        var plugin_run: PluginRun = .{};
        return &plugin_run;
    }

    pub fn plugin(self: *Build, opts: InitOptions.PluginOptions) void {
        _ = self.addPlugin(opts);
    }

    pub fn addElement(self: *Build, options: AddElementOptions) void {
        self.injections_step.add(options);
    }
};

const colors = struct {
    pub const dim: []const u8 = "\x1b[2m";
    pub const reset: []const u8 = "\x1b[0m";
};
