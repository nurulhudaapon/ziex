const std = @import("std");
const Spinner = @import("../../tui/main.zig").Spinner;

/// Shared per-process context threaded through CLI commands.
/// Carries the working `Io` and `Environ.Map` provided by
/// `std.process.Init` in `main`.
///
/// The single-threaded global `Io` (`std.Io.Threaded.global_single_threaded`)
/// has a `failing` allocator and cannot be used for any operation that
/// allocates (e.g. `std.process.spawn`). Commands must use this context's
/// `io` instead.
pub const AppContext = struct {
    io: std.Io,
    environ_map: *std.process.Environ.Map,
};

/// Per-command execution context passed to each command's `run` function.
pub const CommandContext = struct {
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    reader: *std.Io.Reader,
    spinner: *Spinner,
    app: *AppContext,
};
