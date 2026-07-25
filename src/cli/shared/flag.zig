const cli = @import("std_cli");

pub const binpath = cli.Argument.init(.binpath, []const u8, .{
    .default_value = "",
    .short = 'b',
    .help = "Binpath of the app in case if you have multiple exe artificats or using custom zig-out directory",
});

pub const build_args = cli.Argument.init(.@"build-args", []const u8, .{
    .default_value = "",
    .short = 'a',
    .help = "Additional build arguments to pass to zig build",
});

pub const zig_path = cli.Argument.init(.@"zig-path", []const u8, .{
    .default_value = "zig",
    .help = "Path to the zig executable",
});

pub const verbose = cli.Argument.init(.verbose, bool, .{
    .default_value = false,
    .short = 'v',
    .help = "Show verbose output",
});

pub const install_prefix = cli.Argument.init(.@"install-prefix", []const u8, .{
    .default_value = "zig-out",
    .short = 'i',
    .help = "Install prefix for the app (default: zig-out)",
});
