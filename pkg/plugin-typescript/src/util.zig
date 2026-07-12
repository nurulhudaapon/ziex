const plugin_system = @import("plugin_system");
const BuildConfig = @import("TypescriptBuildConfig.zig");

pub const Options = plugin_system.ExcludeFields(BuildConfig, &.{ "project", "inputs" });

pub fn options(config: BuildConfig) Options {
    return plugin_system.options(Options, config);
}
