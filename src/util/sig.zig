const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const windows = std.os.windows;

const native_os = builtin.os.tag;
const is_posix = switch (native_os) {
    .linux, .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos, .freebsd, .netbsd, .dragonfly, .openbsd, .serenity, .illumos => true,
    else => false,
};
const is_windows = native_os == .windows;

pub const max_watches = 16;
pub const max_listeners = 8;

/// Forceful terminate: `SIG.KILL` on POSIX, `SIG.TERM` on Windows (no KILL).
pub const force_kill: posix.SIG = if (@hasField(posix.SIG, "KILL")) .KILL else .TERM;

const win_true: windows.BOOL = .TRUE;
const win_false: windows.BOOL = .FALSE;

/// Watched target: `+pid` | `-pgid` | `0` empty. POSIX-only encoding.
const WatchSlot = std.atomic.Value(i32);

var installed: std.atomic.Value(bool) = .init(false);
var interrupted_flag: std.atomic.Value(bool) = .init(false);
var received_signo: std.atomic.Value(u8) = .init(0);

var wake_r: if (is_posix) posix.fd_t else void = if (is_posix) -1 else {};
var wake_w: if (is_posix) posix.fd_t else void = if (is_posix) -1 else {};
var notifier: ?std.Thread = null;
var notifier_stop: std.atomic.Value(bool) = .init(false);

var watches: [max_watches]WatchSlot = @splat(.init(0));

const Listener = *const fn () void;
var listeners_mu: std.atomic.Mutex = .unlocked;
var listeners: [max_listeners]?Listener = @splat(null);

var prev_int: if (is_posix) ?posix.Sigaction else void = if (is_posix) null else {};
var prev_term: if (is_posix) ?posix.Sigaction else void = if (is_posix) null else {};

pub const InstallError = error{
    AlreadyInstalled,
    SystemFdQuotaExceeded,
    ProcessFdQuotaExceeded,
    Unexpected,
} || std.Thread.SpawnError;

pub fn install() InstallError!void {
    if (installed.swap(true, .acq_rel)) return error.AlreadyInstalled;

    interrupted_flag.store(false, .release);
    received_signo.store(0, .release);
    notifier_stop.store(false, .release);
    clearWatches();

    if (comptime is_windows) {
        if (SetConsoleCtrlHandler(windowsCtrlHandler, win_true) == win_false) {
            installed.store(false, .release);
            return error.Unexpected;
        }
        return;
    }

    if (comptime is_posix) {
        const pipe = createWakePipe() catch |err| {
            installed.store(false, .release);
            return err;
        };
        wake_r = pipe[0];
        wake_w = pipe[1];
        errdefer {
            closeFd(wake_r);
            closeFd(wake_w);
            wake_r = -1;
            wake_w = -1;
            installed.store(false, .release);
        }

        var old_int: posix.Sigaction = undefined;
        var old_term: posix.Sigaction = undefined;
        const act = posix.Sigaction{
            .handler = .{ .handler = posixSignalHandler },
            .mask = posix.sigemptyset(),
            .flags = posix.SA.RESTART,
        };
        posix.sigaction(posix.SIG.INT, &act, &old_int);
        posix.sigaction(posix.SIG.TERM, &act, &old_term);
        prev_int = old_int;
        prev_term = old_term;

        notifier = std.Thread.spawn(.{}, notifierMain, .{}) catch |err| {
            closeFd(wake_r);
            closeFd(wake_w);
            wake_r = -1;
            wake_w = -1;
            installed.store(false, .release);
            return err;
        };
    }
}

pub fn uninstall() void {
    if (!installed.swap(false, .acq_rel)) return;

    if (comptime is_windows) {
        _ = SetConsoleCtrlHandler(windowsCtrlHandler, win_false);
    } else if (comptime is_posix) {
        if (prev_int) |old| posix.sigaction(posix.SIG.INT, &old, null);
        if (prev_term) |old| posix.sigaction(posix.SIG.TERM, &old, null);
        prev_int = null;
        prev_term = null;

        notifier_stop.store(true, .release);
        if (wake_w >= 0) {
            closeFd(wake_w);
            wake_w = -1;
        }
        if (notifier) |t| {
            t.join();
            notifier = null;
        }
        if (wake_r >= 0) {
            closeFd(wake_r);
            wake_r = -1;
        }
    }

    clearListeners();
    clearWatches();
    interrupted_flag.store(false, .release);
    received_signo.store(0, .release);
}

pub fn interrupted() bool {
    return interrupted_flag.load(.acquire);
}

pub fn received() ?posix.SIG {
    const n = received_signo.load(.acquire);
    if (n == 0) return null;
    return @fromBackingInt(@intCast(n));
}

pub fn takeSignal() ?posix.SIG {
    if (!interrupted_flag.swap(false, .acq_rel)) {
        _ = received_signo.swap(0, .acq_rel);
        return null;
    }
    const n = received_signo.swap(0, .acq_rel);
    if (n == 0) return null;
    return @fromBackingInt(@intCast(n));
}

pub fn wakeFd() ?posix.fd_t {
    if (comptime is_posix) {
        if (wake_r < 0) return null;
        return wake_r;
    }
    return null;
}

pub fn drain() void {
    if (comptime is_posix) {
        if (wake_r < 0) return;
        var buf: [64]u8 = undefined;
        while (true) {
            const rc = posix.system.read(wake_r, &buf, buf.len);
            switch (posix.errno(rc)) {
                .SUCCESS => {
                    if (rc == 0) return;
                    continue;
                },
                else => return,
            }
        }
    }
}

pub fn watchPid(pid: posix.pid_t) void {
    if (comptime is_posix) {
        if (pid <= 0) return;
        addWatch(@intCast(pid));
    }
}

/// Spawn with `.pgid = 0` so `child.id` is the group leader.
pub fn watchGroup(pgid: posix.pid_t) void {
    if (comptime is_posix) {
        if (pgid <= 0) return;
        addWatch(-@as(i32, @intCast(pgid)));
    }
}

pub fn unwatchPid(pid: posix.pid_t) void {
    if (comptime is_posix) {
        if (pid <= 0) return;
        removeWatch(@intCast(pid));
    }
}

pub fn unwatchGroup(pgid: posix.pid_t) void {
    if (comptime is_posix) {
        if (pgid <= 0) return;
        removeWatch(-@as(i32, @intCast(pgid)));
    }
}

pub fn clearWatches() void {
    for (&watches) |*slot| slot.store(0, .release);
}

pub fn killWatches(signal: posix.SIG) void {
    if (comptime is_posix) {
        for (&watches) |*slot| {
            const encoded = slot.load(.acquire);
            if (encoded == 0) continue;
            rawKill(@intCast(encoded), signal);
        }
    }
}

pub fn killProcessGroup(pgid: posix.pid_t, signal: posix.SIG) void {
    if (comptime is_windows) {
        // No process groups; `pgid` is the process HANDLE from Child.id.
        windowsTerminate(pgid);
    } else if (comptime is_posix) {
        if (pgid <= 0) return;
        rawKill(-pgid, signal);
    }
}

pub fn killPid(pid: posix.pid_t, signal: posix.SIG) void {
    if (comptime is_windows) {
        windowsTerminate(pid);
    } else if (comptime is_posix) {
        if (pid <= 0) return;
        rawKill(pid, signal);
    }
}

pub fn isAlive(pid: posix.pid_t) bool {
    if (comptime is_windows) {
        const timeout: windows.LARGE_INTEGER = -1; // 100ns units; -1 = 100ns
        return switch (windows.ntdll.NtWaitForSingleObject(pid, .FALSE, &timeout)) {
            windows.NTSTATUS.WAIT_0 => false,
            .TIMEOUT => true,
            else => true,
        };
    } else if (comptime is_posix) {
        if (pid <= 0) return false;
        const rc = posix.system.kill(pid, @fromBackingInt(@intCast(0)));
        return switch (posix.errno(rc)) {
            .SUCCESS, .PERM => true,
            .SRCH => false,
            else => true,
        };
    }
    return false;
}

pub fn waitPidExit(pid: posix.pid_t, timeout_ms: u64) bool {
    if (comptime is_windows) {
        if (timeout_ms == 0) return !isAlive(pid);
        // NtWaitForSingleObject timeout is relative, in 100ns units, negative = relative.
        const hundred_ns: i64 = -@as(i64, @intCast(timeout_ms)) *% 10_000;
        const timeout: windows.LARGE_INTEGER = hundred_ns;
        return switch (windows.ntdll.NtWaitForSingleObject(pid, .FALSE, &timeout)) {
            windows.NTSTATUS.WAIT_0 => true,
            else => !isAlive(pid),
        };
    }
    if (!isAlive(pid)) return true;
    var waited: u64 = 0;
    while (waited < timeout_ms) : (waited += 20) {
        sleepMs(20);
        if (!isAlive(pid)) return true;
    }
    return !isAlive(pid);
}

/// Deadline-based sleep safe on the notifier thread (EINTR-tolerant).
pub fn sleepMs(ms: u64) void {
    if (ms == 0) return;
    if (comptime is_windows) {
        std.Thread.sleep(ms *% std.time.ns_per_ms);
    } else if (comptime is_posix) {
        const start_ms = monoMs();
        while (true) {
            const elapsed = monoMs() -% start_ms;
            if (elapsed >= ms) return;
            const left = ms - elapsed;
            var req = posix.timespec{
                .sec = @intCast(left / 1000),
                .nsec = @intCast((left % 1000) * std.time.ns_per_ms),
            };
            const rc = posix.system.nanosleep(&req, null);
            switch (posix.errno(rc)) {
                .SUCCESS => return,
                .INTR => continue,
                else => return,
            }
        }
    }
}

pub fn addListener(listener: Listener) void {
    lockListeners();
    defer unlockListeners();
    for (&listeners) |*slot| {
        if (slot.* == null) {
            slot.* = listener;
            return;
        }
    }
}

pub fn removeListener(listener: Listener) void {
    lockListeners();
    defer unlockListeners();
    for (&listeners) |*slot| {
        if (slot.*) |existing| {
            if (existing == listener) {
                slot.* = null;
                return;
            }
        }
    }
}

/// Exit the whole process with status `128 + signo`. Prefer over `std.process.exit`
/// from the notifier thread (avoids joining other threads).
pub fn raiseDefault(signal: posix.SIG) noreturn {
    const code: u8 = 128 +% @as(u8, @intCast(@backingInt(signal)));

    if (comptime is_windows) {
        std.process.exit(code);
    } else if (comptime native_os == .linux) {
        std.os.linux.exit_group(@as(i32, @intCast(code)));
    } else if (comptime is_posix) {
        const act = posix.Sigaction{
            .handler = .{ .handler = posix.SIG.DFL },
            .mask = posix.sigemptyset(),
            .flags = posix.SA.RESETHAND,
        };
        posix.sigaction(signal, &act, null);
        rawKill(posix.system.getpid(), signal);
        std.c._exit(@intCast(code));
    } else {
        std.process.abort();
    }
}

fn monoMs() u64 {
    if (comptime native_os == .linux) {
        var ts: std.os.linux.timespec = undefined;
        _ = std.os.linux.clock_gettime(.MONOTONIC, &ts);
        return @as(u64, @intCast(ts.sec)) *% 1000 +% @as(u64, @intCast(@divTrunc(ts.nsec, std.time.ns_per_ms)));
    }
    return 0;
}

fn addWatch(encoded: i32) void {
    for (&watches) |*slot| {
        if (slot.cmpxchgStrong(0, encoded, .acq_rel, .acquire) == null) return;
    }
}

fn removeWatch(encoded: i32) void {
    for (&watches) |*slot| {
        _ = slot.cmpxchgStrong(encoded, 0, .acq_rel, .acquire);
    }
}

fn rawKill(pid: posix.pid_t, signal: posix.SIG) void {
    if (comptime is_posix) {
        _ = posix.system.kill(pid, signal);
    }
}

fn windowsTerminate(handle: windows.HANDLE) void {
    if (comptime !is_windows) return;
    _ = windows.ntdll.RtlReportSilentProcessExit(handle, @fromBackingInt(1));
    switch (windows.ntdll.NtTerminateProcess(handle, @fromBackingInt(1))) {
        .SUCCESS, .PROCESS_IS_TERMINATING => {},
        else => {},
    }
}

fn wake() void {
    if (comptime is_posix) {
        if (wake_w < 0) return;
        var byte: [1]u8 = .{1};
        _ = posix.system.write(wake_w, &byte, 1);
    }
}

fn recordAndDispatch(signo: u8) void {
    received_signo.store(signo, .release);
    interrupted_flag.store(true, .release);
    killWatches(posix.SIG.TERM);
    if (comptime is_windows) {
        notifyListeners();
    } else {
        wake();
    }
}

fn posixSignalHandler(signo: posix.SIG) callconv(.c) void {
    recordAndDispatch(@intCast(@backingInt(signo)));
}

fn notifierMain() void {
    if (comptime is_posix) {
        var buf: [16]u8 = undefined;
        while (!notifier_stop.load(.acquire)) {
            const rc = posix.system.read(wake_r, &buf, buf.len);
            switch (posix.errno(rc)) {
                .SUCCESS => {
                    if (rc == 0) return;
                    notifyListeners();
                },
                .INTR, .AGAIN => continue,
                else => return,
            }
        }
    }
}

fn clearListeners() void {
    lockListeners();
    defer unlockListeners();
    @memset(&listeners, null);
}

fn notifyListeners() void {
    var copy: [max_listeners]?Listener = undefined;
    {
        lockListeners();
        defer unlockListeners();
        copy = listeners;
    }
    for (copy) |slot| {
        if (slot) |listener| listener();
    }
}

fn lockListeners() void {
    while (!listeners_mu.tryLock()) std.atomic.spinLoopHint();
}

fn unlockListeners() void {
    listeners_mu.unlock();
}

fn createWakePipe() InstallError![2]posix.fd_t {
    if (comptime is_posix) {
        const flags: posix.O = .{ .CLOEXEC = true };
        var fds: [2]posix.fd_t = undefined;

        if (@TypeOf(posix.system.pipe2) != void) {
            switch (posix.errno(posix.system.pipe2(&fds, flags))) {
                .SUCCESS => {},
                .NFILE => return error.SystemFdQuotaExceeded,
                .MFILE => return error.ProcessFdQuotaExceeded,
                else => return error.Unexpected,
            }
        } else {
            switch (posix.errno(posix.system.pipe(&fds))) {
                .SUCCESS => {},
                .NFILE => return error.SystemFdQuotaExceeded,
                .MFILE => return error.ProcessFdQuotaExceeded,
                else => return error.Unexpected,
            }
            errdefer {
                closeFd(fds[0]);
                closeFd(fds[1]);
            }
            for (fds) |fd| {
                switch (posix.errno(posix.system.fcntl(fd, posix.F.SETFD, @as(u32, posix.FD_CLOEXEC)))) {
                    .SUCCESS => {},
                    else => return error.Unexpected,
                }
            }
        }
        return fds;
    }
    return error.Unexpected;
}

fn closeFd(fd: posix.fd_t) void {
    if (comptime is_posix) {
        if (fd < 0) return;
        _ = posix.system.close(fd);
    }
}

fn windowsCtrlHandler(ctrl_type: windows.DWORD) callconv(.winapi) windows.BOOL {
    switch (ctrl_type) {
        0, 1, 2 => {
            recordAndDispatch(@backingInt(posix.SIG.INT));
            return win_true;
        },
        else => return win_false,
    }
}

extern "kernel32" fn SetConsoleCtrlHandler(
    HandlerRoutine: ?*const fn (windows.DWORD) callconv(.winapi) windows.BOOL,
    Add: windows.BOOL,
) callconv(.winapi) windows.BOOL;
