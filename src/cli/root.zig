//! Public ZX CLI argument surface (`@import("cli_args")`).
//! Command metadata only - no run implementations / host-only deps.

const builtin = @import("builtin");
const std_cli = @import("std_cli");
const flags = @import("shared/flag.zig");

pub const Command = std_cli.Command;
pub const Argument = std_cli.Argument;

pub const version: Command = .{
    .name = .version,
    .help_short = "Show CLI version",
};

pub const init: Command = .{
    .name = .init,
    .help_short = "Initialize a new ZX project in the current directory",
    .named_args = &.{
        Argument.init(.template, []const u8, .{
            .default_value = "default",
            .short = 't',
            .help = "Template to use: a builtin (default, docker) or any github:ziex-dev/template-<name> (e.g. cloudflare, vercel)",
        }),
        Argument.init(.force, bool, .{
            .default_value = false,
            .short = 'f',
            .help = "Force initialization even if the directory is not empty",
        }),
        Argument.init(.existing, bool, .{
            .default_value = false,
            .help = "Initialize ZX in an existing project",
        }),
    },
    .positional_args = &.{
        Argument.init(.path, ?[]const u8, .{
            .help = "Path to initialize the project in (default: current directory)",
        }),
    },
};

pub const dev: Command = .{
    .name = .dev,
    .help_short = "Start the app in development mode with rebuild on change",
    .named_args = &.{
        flags.binpath,
        flags.build_args,
        flags.zig_path,
        flags.install_prefix,
        Argument.init(.port, u32, .{
            .default_value = 0,
            .short = 'p',
            .help = "Port to listen on (default: PORT env, or 3000). Uses the next free port if busy",
        }),
        Argument.init(.@"tui-progress", bool, .{
            .default_value = true,
            .help = "Show full build progress output from zig build",
        }),
        Argument.init(.@"tui-underline", bool, .{
            .default_value = true,
            .help = "Show underlined status messages",
        }),
        Argument.init(.@"tui-spinner", bool, .{
            .default_value = false,
            .help = "Show spinner for status messages",
        }),
        Argument.init(.@"tui-clear", bool, .{
            .default_value = false,
            .help = "Clear the terminal before every restart",
        }),
    },
};

pub const serve: Command = .{
    .name = .serve,
    .help_short = "Run the server",
    .named_args = &.{
        Argument.init(.port, u32, .{
            .default_value = 0,
            .short = 'p',
            .help = "Port to listen on (sets PORT; default: PORT env, or 3000)",
        }),
        flags.binpath,
        flags.zig_path,
        Argument.init(.@"build-args", []const u8, .{
            .default_value = "-Doptimize=ReleaseFast",
            .short = 'a',
            .help = "Additional build arguments to pass to zig build",
        }),
    },
};

pub const build: Command = .{
    .name = .build,
    .help_short = "Build the app (equivalent to `zig build`)",
    .named_args = &.{
        flags.build_args,
        flags.zig_path,
    },
};

pub const transpile: Command = .{
    .name = .transpile,
    .help_short = "Transpile a .zx file or directory to zig source code.",
    .named_args = &.{
        Argument.init(.outdir, []const u8, .{
            .default_value = ".zx",
            .short = 'o',
            .help = "Output directory",
        }),
        Argument.init(.@"copy-only", bool, .{
            .default_value = false,
            .help = "Copy only the files to the output directory",
        }),
        flags.verbose,
        Argument.init(.map, []const u8, .{
            .default_value = "none",
            .help = "Generate source map",
        }),
        Argument.init(.@"dep-file", []const u8, .{
            .default_value = "",
            .help = "Write a Make-format dependency file listing all transpiled input files",
        }),
        Argument.init(.@"cache-dir", []const u8, .{
            .default_value = "",
            .help = "Persistent transpile cache directory (mtime + Transpile.shape; survives zig-cache invalidation)",
        }),
        Argument.init(.@"base-path", []const u8, .{
            .default_value = "",
            .help = "Base path for the application (e.g., /test)",
        }),
        Argument.init(.manifest, []const u8, .{
            .default_value = "",
            .help = "Centralized app manifest path (zig-out/manifest/app.zon)",
        }),
        Argument.init(.@"build-injections", []const u8, .{
            .default_value = "",
            .help = "Build-managed injections to merge into the app manifest",
        }),
        Argument.init(.@"exe-path", []const u8, .{
            .default_value = "",
            .help = "Path to the executable",
        }),
    },
    .positional_args = &.{
        Argument.init(.path, []const u8, .{
            .help = "Path to .zx file or directory",
        }),
    },
};

pub const fmt: Command = .{
    .name = .fmt,
    .help_short = "Format .zx files or directories.",
    .named_args = &.{
        Argument.init(.stdio, bool, .{
            .default_value = false,
            .help = "Read from stdin and write formatted output to stdout",
        }),
        Argument.init(.stdout, bool, .{
            .default_value = false,
            .help = "Write formatted output to stdout instead of disk",
        }),
        Argument.init(.@"error", bool, .{
            .default_value = false,
            .help = "Read zig build error output from stdin and pretty-print it (e.g. zig build 2>&1 | zx fmt --error)",
        }),
    },
    .positional_args = &.{
        Argument.init(.paths, []const []const u8, .{
            .count = .unlimited,
            .default_value = &.{},
            .help = "Paths to .zx files or directories",
        }),
    },
};

pub const lsp: Command = .{
    .name = .lsp,
    .help_short = "Start the Ziex language server",
};

pub const @"export": Command = .{
    .name = .@"export",
    .help_short = "Export the site to a static HTML directory",
    .named_args = &.{
        Argument.init(.outdir, []const u8, .{
            .default_value = "dist",
            .short = 'o',
            .help = "Output directory",
        }),
        flags.binpath,
        flags.zig_path,
        Argument.init(.@"build-args", []const u8, .{
            .default_value = "--release=small",
            .help = "Additional arguments to pass to zig build (e.g., -Doptimize=ReleaseFast)",
        }),
    },
};

pub const bundle: Command = .{
    .name = .bundle,
    .help_short = "Bundle the site into a deployable directory",
    .named_args = &.{
        Argument.init(.outdir, []const u8, .{
            .default_value = "bundle",
            .short = 'o',
            .help = "Output directory",
        }),
        flags.binpath,
        flags.install_prefix,
    },
};

pub const update: Command = .{
    .name = .update,
    .help_short = "Update the version of ZX dependency",
    .named_args = &.{
        Argument.init(.version, []const u8, .{
            .default_value = "latest",
            .short = 'v',
            .help = "Version to update to",
        }),
        Argument.init(.dev, bool, .{
            .default_value = false,
            .help = "Update to the latest commit on the main branch instead of the latest release",
        }),
        flags.zig_path,
    },
};

pub const upgrade: Command = .{
    .name = .upgrade,
    .help_short = "Upgrade the version of ZX CLI",
    .named_args = &.{
        Argument.init(.version, []const u8, .{
            .default_value = "latest",
            .short = 'v',
            .help = "Version to update to",
        }),
    },
};

/// Full host CLI command list (docs / reference).
pub const commands: []const Command = &.{
    version,
    init,
    dev,
    serve,
    build,
    transpile,
    fmt,
    lsp,
    @"export",
    bundle,
    update,
    upgrade,
};

const os_commands: []const Command = switch (builtin.os.tag) {
    .wasi, .freestanding => &.{ version, transpile, fmt },
    else => commands,
};

pub const root_command: Command = .{
    .name = .zx,
    .help =
    \\Ziex is a framework for building web applications with Zig.
    \\
    ,
    .help_short = "Ziex framework CLI",
    .subcommands = os_commands,
};
