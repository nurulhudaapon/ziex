/// Configuration options for initializing a ZX project in your build.zig.
///
/// This struct provides comprehensive control over how ZX transpiles and builds
/// your website, including CLI configuration, experimental features, and plugin integration.
///
/// ## Usage Example
/// ```zig
/// const zx_options = zx.ZxInitOptions{
///     .site = .{ .path = "site" },
///     .cli = .{
///         .path = null, // Use ZX from dependency
///         .steps = .{
///             .serve = "serve",
///             .dev = "dev",
///         },
///     },
/// };
/// try zx.init(b, exe, zx_options);
/// ```
pub const ZxInitOptions = @This();

/// Configuration for the ZX CLI executable and build steps.
pub const CliOptions = struct {
    /// Custom names for ZX build steps.
    ///
    /// Configure which Zig build steps to create and what names to give them.
    /// Set any step to `null` to disable it.
    pub const Steps = struct {
        /// Step name for running the development server (default: "serve")
        serve: []const u8 = "serve",
        /// Step name for development mode with hot-reload (default: null/disabled)
        dev: ?[]const u8 = null,
        /// Step name for exporting static site (default: null/disabled)
        @"export": ?[]const u8 = null,
        /// Step name for bundling the website (default: null/disabled)
        bundle: ?[]const u8 = null,
    };

    /// Path to the ZX CLI executable.
    ///
    /// - If `null`: Uses the ZX CLI from the ZX dependency source (recommended)
    /// - If set to `"zx"`: Uses the ZX CLI from the system PATH
    /// - Otherwise: Uses the specified path to a ZX CLI executable
    path: ?[]const u8 = null,

    /// Configuration for which build steps to create.
    ///
    /// If `null`, only the default "serve" step will be created.
    steps: ?Steps = .{
        .serve = "serve",
    },
};

/// Configuration for the ZX site directory.
const SiteOptions = struct {
    /// Path to the ZX site source directory.
    ///
    /// This directory should contain your `.zx` template files, layouts,
    /// and other site assets. Defaults to "site" if not specified in ZxInitOptions.
    path: []const u8,
};

/// Experimental features that may change in future versions.
const ExperimentalOptions = struct {
    /// Enable Client-Side Rendering (CSR) support.
    ///
    /// When enabled, ZX will compile a WebAssembly module for client-side
    /// interactivity and hydration. This generates additional build artifacts
    /// in the assets directory.
    ///
    /// Default: `false`
    enabled_csr: bool = false,
};

/// Configuration for build plugins that extend ZX functionality.
pub const PluginOptions = struct {
    /// Command-based plugin step configuration.
    pub const PluginStepCommand = struct {
        /// When to execute this plugin in the build lifecycle.
        type: enum {
            /// Run before ZX transpilation occurs
            before_transpile,
            /// Run after ZX transpilation completes
            after_transpile,
        },

        /// Command arguments to execute.
        ///
        /// The first element should be the executable name or path.
        /// Subsequent elements are arguments passed to that executable.
        ///
        /// ## Output Directory Placeholder
        /// Use `{outdir}` in any argument to reference the transpile output directory.
        /// You can append a subpath after `{outdir}`, e.g., `{outdir}/assets/styles.css`
        ///
        /// ## Example
        /// ```zig
        /// .args = &.{
        ///     "node_modules/.bin/tailwindcss",
        ///     "-i", "site/styles.css",
        ///     "-o", "{outdir}/assets/styles.css"
        /// }
        /// ```
        args: []const []const u8,
    };

    /// A plugin step that can be executed during the build.
    const PluginStep = union(enum) {
        /// Execute a shell command
        command: PluginStepCommand,
    };

    /// Human-readable name for this plugin.
    name: []const u8,

    /// List of steps this plugin should execute during the build.
    steps: []const PluginStep,
};

/// Site directory configuration.
///
/// If `null`, defaults to `site` directory in your project root.
/// Override this to use a custom site source directory.
site: ?SiteOptions = null,

/// ZX CLI configuration.
///
/// Controls which ZX CLI executable to use and which build steps to create.
/// If `null`, uses default configuration with ZX CLI from dependency source.
cli: ?CliOptions = null,

/// Experimental features configuration.
///
/// Enable cutting-edge ZX features that may have breaking changes in the future.
/// If `null`, all experimental features are disabled.
experimental: ?ExperimentalOptions = null,

/// Plugin configurations for extending the build process.
///
/// Plugins allow you to run custom commands (like CSS preprocessors, asset optimizers, etc.)
/// at specific points in the ZX build lifecycle.
/// If `null`, no plugins are registered.
plugins: ?[]const PluginOptions = null,
