const std = @import("std");

pub const BuildConfig = @import("src/BunBuildConfig.zig");
pub const Build = struct {
    name: ?[]const u8 = null,
    config: BuildConfig,
};

pub const Output = struct {
    dir: std.Build.LazyPath,
    run: *std.Build.Step.Run,
};

pub var bun_path: ?std.Build.LazyPath = null;

pub fn setBunPath(path: std.Build.LazyPath) void {
    bun_path = path;
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
    const plugin_exe = dep.artifact("bunjs");

    var arena = std.heap.ArenaAllocator.init(b.allocator);
    const alloc = arena.allocator();

    // Create config for single build (outdir is NOT in config — injected by exe from CLI arg)
    var obj = std.json.ObjectMap.init(alloc);
    try obj.put("name", .{ .string = build_item.name orelse "bun build" });
    const config_val = try build_item.config.toJsonValue(b, alloc);
    try obj.put("config", config_val);
    var arr = std.json.Array.init(alloc);
    try arr.append(.{ .object = obj });
    const json_buf = try std.json.Stringify.valueAlloc(alloc, std.json.Value{ .array = arr }, .{});

    const run = b.addRunArtifact(plugin_exe);

    const step_name = b.fmt("build {s} {s}{s}{s}", .{ deriveName(b, build_item, &run.step), colors.dim, "bun", colors.reset });
    run.setName(step_name);
    run.setStdIn(.{ .bytes = json_buf });

    // Zig-managed output directory (enables build caching)
    run.addArg("--outdir");
    const outdir = run.addOutputDirectoryArg("dist");

    if (bun_path) |bp| {
        run.addArg("--bun-path");
        run.addFileArg(bp);
    }

    for (build_item.config.entrypoints) |ep| run.addFileInput(ep);

    return .{ .dir = outdir, .run = run };
}

fn deriveName(b: *std.Build, self: Build, step: *std.Build.Step) []const u8 {
    if (self.name) |n| return n;
    if (self.config.entrypoints.len > 0) {
        const ep = self.config.entrypoints[0];
        const ep_name = ep.basename(b, step);
        return ep_name;
    } else {
        return "";
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "bunjs",
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
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the plugin");
    run_step.dependOn(&run_cmd.step);
}

const colors = struct {
    pub const dim: []const u8 = "\x1b[2m";
    pub const reset: []const u8 = "\x1b[0m";
};
