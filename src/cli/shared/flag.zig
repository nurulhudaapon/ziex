pub const binpath_flag = zli.Flag{
    .name = "binpath",
    .shortcut = "b",
    .description = "Binpath of the app in case if you have multiple exe artificats or using custom zig-out directory",
    .type = .String,
    .default_value = .{ .String = "" },
};

pub const build_args = zli.Flag{
    .name = "build-args",
    .shortcut = "a",
    .description = "Additional build arguments to pass to zig build",
    .type = .String,
    .default_value = .{ .String = "" },
    .hidden = true,
};

pub const zig_path_flag = zli.Flag{
    .name = "zig-path",
    .description = "Path to the zig executable",
    .type = .String,
    .default_value = .{ .String = "zig" },
    .hidden = true,
};

pub const verbose_flag = zli.Flag{
    .name = "verbose",
    .shortcut = "v",
    .description = "Show verbose output",
    .type = .Bool,
    .default_value = .{ .Bool = false },
};

pub const install_prefix_flag = zli.Flag{
    .name = "install-prefix",
    .shortcut = "i",
    .description = "Install prefix for the app (default: zig-out)",
    .type = .String,
    .default_value = .{ .String = "zig-out" },
};

const zli = @import("zli");
