const plugin_system = @import("plugin_system");
const BuildConfig = @import("EsbuildBuildConfig.zig");

pub const Options = plugin_system.ExcludeFields(BuildConfig, &.{"entrypoints"});

pub fn options(config: BuildConfig) Options {
    return plugin_system.options(Options, config);
}
