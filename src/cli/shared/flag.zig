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

const zli = @import("zli");
