/// Configuration options for initializing a ZX project in your build.zig.
///
/// This struct provides comprehensive control over how ZX transpiles and builds
/// your website, including CLI configuration, experimental features, and plugin integration.
///
/// ## Usage Example
/// ```zig
/// const zx_options: zx.ZxInitOptions = .{
///     .site = .{ .path = "site" },
///     .cli = .{
///         .path = null, // Use ZX from dependency
///         .steps = .{
///             .dev = "dev",
///             .serve = "serve",
///         },
///     },
/// };
/// try zx.init(b, exe, zx_options);
/// ```
const std = @import("std");
const LazyPath = std.Build.LazyPath;

/// Configuration for the ZX CLI executable and build steps.
pub const CliOptions = struct {
    /// Custom names for ZX build steps.
    ///
    /// Configure which Zig build steps to create and what names to give them.
    /// Set any step to `null` to disable it.
    pub const Steps = struct {
        /// Step name for development mode with hot-reload (default: null/disabled)
        dev: ?[]const u8 = null,
        /// Step name for running the site in production build without hot-reload (default: "serve")
        serve: ?[]const u8 = null,
        /// Step name for exporting static site (default: null/disabled)
        @"export": ?[]const u8 = null,
        /// Step name for bundling the website (default: null/disabled)
        bundle: ?[]const u8 = null,

        pub const default: Steps = .{ .dev = "dev", .serve = "serve" };
    };

    /// Path to the ZX CLI executable.
    ///
    /// - If `null`: Uses the ZX CLI from the ZX dependency source (recommended)
    /// - If set to `"zx"`: Uses the ZX CLI from the system PATH
    /// - Otherwise: Uses the specified path to a ZX CLI executable
    path: ?LazyPath = null,

    /// Configuration for which build steps to create.
    ///
    /// If `null`, only the default "serve" step will be created.
    steps: ?Steps = .{
        .dev = "dev",
    },
};

/// Configuration for the ZX app directory.
pub const AppOptions = struct {
    /// Path to the ZX app source directory.
    ///
    /// This directory should contain your `.zx` template files, layouts,
    /// and other app assets. Defaults to "app" if not specified in ZxInitOptions.
    path: LazyPath,

    /// Copy embedded `.zx` source files to the transpile output directory.
    ///
    /// When enabled, any `.zx` files referenced via `@embedFile` in your templates
    /// will be copied to the output directory alongside the generated `.zig` files,
    /// and the `@embedFile` paths will be updated to reference the local copies.
    ///
    /// This is useful when you want to display source code examples in your app
    /// and need the files accessible within the package boundary.
    ///
    /// Default: `false`
    copy_embedded_sources: bool = false,
};

pub const ClientOptions = struct {
    pub const default: ClientOptions = .{};

    jsglue_href: ?[]const u8 = null,
};

/// Experimental features that may change in future versions.
const ExperimentalOptions = struct {};

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

        /// Command to execute.
        ///
        /// Use `{outdir}` in `LazyPath` arguments to reference the transpile output directory.
        run: *std.Build.Step.Run,
    };

    /// A plugin step that can be executed during the build.
    pub const PluginStep = union(enum) {
        /// Execute a shell command
        command: PluginStepCommand,
    };

    /// Human-readable name for this plugin.
    name: []const u8,

    /// List of steps this plugin should execute during the build.
    steps: []const PluginStep,
};

/// App directory configuration.
///
/// If `null`, defaults to `app` directory in your project root.
/// Override this to use a custom app source directory.
app: ?AppOptions = null,

/// ZX CLI configuration.
///
/// Controls which ZX CLI executable to use and which build steps to create.
/// If `null`, uses default configuration with ZX CLI from dependency source.
cli: ?CliOptions = null,

/// Enable Client-Side Rendering (CSR) support.
///
/// When enabled, ZX will compile a WebAssembly module for client-side
/// interactivity and hydration. This generates additional build artifacts
/// in the assets directory.
client: ?ClientOptions = .default,

/// Experimental features configuration.
///
/// Enable cutting-edge ZX features that may have breaking changes in the future.
/// If `null`, all experimental features are disabled.
experimental: ?ExperimentalOptions = null,

// /// Plugin configurations for extending the build process.
// ///
// /// Plugins allow you to run custom commands (like CSS preprocessors, asset optimizers, etc.)
// /// at specific points in the ZX build lifecycle.
// /// If `null`, no plugins are registered.
// plugins: ?[]const PluginOptions = null,
