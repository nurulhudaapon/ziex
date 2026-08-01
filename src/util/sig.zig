const std = @import("std");
const builtin = @import("builtin");

const win_true: std.os.windows.BOOL = std.os.windows.BOOL.TRUE;
const win_false: std.os.windows.BOOL = .FALSE;

var g_on_shutdown: ?*const fn () void = null;

fn trigger() void {
    if (g_on_shutdown) |f| f();
}

fn posixSignalHandler(_: std.posix.SIG) callconv(.c) void {
    trigger();
}

fn registerPosixHandlers() void {
    const act = std.posix.Sigaction{
        .handler = .{ .handler = posixSignalHandler },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.INT, &act, null);
    std.posix.sigaction(std.posix.SIG.TERM, &act, null);
}

fn windowsCtrlHandler(ctrl_type: std.os.windows.DWORD) callconv(.winapi) std.os.windows.BOOL {
    switch (ctrl_type) {
        // CTRL_C_EVENT=0, CTRL_BREAK_EVENT=1, CTRL_CLOSE_EVENT=2
        0, 1, 2 => {
            trigger();
            return win_true;
        },
        else => return win_false,
    }
}

extern "kernel32" fn SetConsoleCtrlHandler(
    HandlerRoutine: ?*const fn (std.os.windows.DWORD) callconv(.winapi) std.os.windows.BOOL,
    Add: std.os.windows.BOOL,
) callconv(.winapi) std.os.windows.BOOL;

/// Install the cross-platform shutdown handlers, invoking `on_shutdown` when
/// the process receives Ctrl+C / SIGINT / SIGTERM (or the Windows console
/// close/break events). No-op on wasi / freestanding targets.
pub fn register(on_shutdown: *const fn () void) void {
    g_on_shutdown = on_shutdown;
    if (comptime builtin.os.tag == .windows) {
        _ = SetConsoleCtrlHandler(windowsCtrlHandler, win_true);
    } else if (comptime builtin.os.tag != .wasi and builtin.os.tag != .freestanding) {
        registerPosixHandlers();
    }
}

/// Clear the registered callback so a stale pointer is never invoked after the
/// owning state is torn down.
pub fn unregister() void {
    g_on_shutdown = null;
}
