const plugin_system = @import("plugin_system");
const BuildConfig = @import("TailwindBuildConfig.zig");

pub const Options = plugin_system.ExcludeFields(BuildConfig, &.{ "input", "base", "sources" });

pub fn options(config: BuildConfig) Options {
    return plugin_system.options(Options, config);
}
