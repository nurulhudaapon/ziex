const std = @import("std");
const util = @import("src/util.zig");

pub const BuildConfig = @import("src/EsbuildBuildConfig.zig");

pub const Build = struct {
    name: ?[]const u8 = null,
    config: BuildConfig,
};

pub const Output = struct {
    dir: std.Build.LazyPath,
    run: *std.Build.Step.Run,
};

pub var esbuild_path: ?std.Build.LazyPath = null;

/// Point at the project's esbuild binary (typically `node_modules/.bin/esbuild`).
pub fn setEsbuildPath(path: std.Build.LazyPath) void {
    esbuild_path = path;
}

pub fn addBuild(b: *std.Build, build_item: Build) Output {
    return innerInitSingle(b, build_item) catch @panic("addBuild");
}

pub fn addBuilds(b: *std.Build, builds: []const Build) []const Output {
    const outputs = b.allocator.alloc(Output, builds.len) catch @panic("OOM");
    for (builds, 0..) |build_item, i| {
        outputs[i] = innerInitSingle(b, build_item) catch @panic("addBuilds");
    }
    return outputs;
}

fn innerInitSingle(b: *std.Build, build_item: Build) !Output {
    const dep = b.dependencyFromBuildZig(@This(), .{});
    const plugin_exe = dep.artifact("esbuild");

    var arena = std.heap.ArenaAllocator.init(b.allocator);
    const alloc = arena.allocator();

    const json_buf = try std.json.Stringify.valueAlloc(alloc, util.options(build_item.config), .{});

    const run = b.addRunArtifact(plugin_exe);

    const step_name = b.fmt("build {s} {s}{s}{s}", .{ deriveName(b, build_item, &run.step), colors.dim, "esbuild", colors.reset });
    run.setName(step_name);
    run.setStdIn(.{ .bytes = json_buf });

    run.addArg("--name");
    run.addArg(build_item.name orelse "esbuild");

    // Zig-managed output directory (enables build caching)
    run.addArg("--outdir");
    const outdir = run.addOutputDirectoryArg("dist");

    // Dep file for transitive dependency tracking (rebuilds when imported files change)
    run.addArg("--dep-file");
    _ = run.addDepFileOutputArg("dist.d");

    // Prefer an explicit path; otherwise resolve the conventional project install.
    const bin = esbuild_path orelse b.path("node_modules/.bin/esbuild");
    run.addArg("--esbuild-path");
    run.addFileArg(bin);

    for (build_item.config.entrypoints) |ep| {
        run.addArg("--entry");
        run.addFileArg(ep);
    }

    return .{ .dir = outdir, .run = run };
}

fn deriveName(b: *std.Build, self: Build, step: *std.Build.Step) []const u8 {
    if (self.name) |n| return n;
    if (self.config.entrypoints.len > 0) {
        const ep = self.config.entrypoints[0];
        // TODO: LazyPath.basename has been removed zig 0.17, figoure out alternative
        // const ep_name = ep.basename(b, step);
        const ep_name = ep.src_path.sub_path;
        _ = step;
        _ = b;
        return ep_name;
    } else {
        return "";
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "esbuild",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    // `zig build run`
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    const run_step = b.step("run", "Run the plugin");
    run_step.dependOn(&run_cmd.step);
}

const colors = struct {
    pub const dim: []const u8 = "\x1b[2m";
    pub const reset: []const u8 = "\x1b[0m";
};
