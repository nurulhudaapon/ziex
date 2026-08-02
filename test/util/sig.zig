const std = @import("std");
const builtin = @import("builtin");
const sig = @import("zx").util.sig;

const posix = std.posix;
const is_posix = switch (builtin.os.tag) {
    .linux, .macos, .ios, .watchos, .tvos, .visionos, .driverkit, .maccatalyst, .freebsd, .netbsd, .dragonfly, .openbsd => true,
    else => false,
};

fn sleepMs(ms: i64) void {
    std.Io.sleep(std.testing.io, .fromMilliseconds(ms), .awake) catch {};
}

fn waitUntil(comptime pred: fn () bool, timeout_ms: u32) bool {
    var waited: u32 = 0;
    while (waited < timeout_ms) : (waited += 10) {
        if (pred()) return true;
        sleepMs(10);
    }
    return pred();
}

test "install + raise SIGINT sets interrupted and notifies listener" {
    if (comptime !is_posix) return error.SkipZigTest;

    if (comptime is_posix) {
        try sig.install();
        defer sig.uninstall();

        const Flag = struct {
            var hit: std.atomic.Value(bool) = .init(false);
            fn onShutdown() void {
                hit.store(true, .release);
            }
        };
        Flag.hit.store(false, .release);
        sig.addListener(Flag.onShutdown);
        defer sig.removeListener(Flag.onShutdown);

        try posix.raise(posix.SIG.INT);

        try std.testing.expect(waitUntil(struct {
            fn p() bool {
                return sig.interrupted();
            }
        }.p, 1000));
        try std.testing.expectEqual(posix.SIG.INT, sig.received().?);

        try std.testing.expect(waitUntil(struct {
            fn p() bool {
                return Flag.hit.load(.acquire);
            }
        }.p, 1000));

        _ = sig.takeSignal();
        try std.testing.expect(!sig.interrupted());
    }
}

test "double install fails" {
    try sig.install();
    defer sig.uninstall();
    try std.testing.expectError(error.AlreadyInstalled, sig.install());
}

test "watchGroup: SIGINT kills supervised process group" {
    if (comptime !is_posix) return error.SkipZigTest;

    if (comptime is_posix) {
        const io = std.testing.io;

        try sig.install();
        defer sig.uninstall();

        var child = try std.process.spawn(io, .{
            .argv = &.{ "sleep", "60" },
            .pgid = 0,
            .stdout = .ignore,
            .stderr = .ignore,
        });
        const pgid = child.id orelse {
            child.kill(io);
            return error.SkipZigTest;
        };
        sig.watchGroup(pgid);
        defer sig.unwatchGroup(pgid);

        try posix.raise(posix.SIG.INT);

        const term = child.wait(io) catch {
            sig.killProcessGroup(pgid, sig.force_kill);
            child.kill(io);
            return error.TestUnexpectedResult;
        };
        switch (term) {
            .signal, .exited => {},
            else => return error.TestUnexpectedResult,
        }

        const probe = posix.kill(-pgid, @enumFromInt(0));
        try std.testing.expectError(error.ProcessNotFound, probe);
    }
}

test "killProcessGroup terminates pgid without requiring a signal" {
    if (comptime !is_posix) return error.SkipZigTest;

    if (comptime is_posix) {
        const io = std.testing.io;

        var child = try std.process.spawn(io, .{
            .argv = &.{ "sleep", "60" },
            .pgid = 0,
            .stdout = .ignore,
            .stderr = .ignore,
        });
        const pgid = child.id orelse {
            child.kill(io);
            return error.SkipZigTest;
        };

        sig.killProcessGroup(pgid, posix.SIG.TERM);
        const term = child.wait(io) catch {
            child.kill(io);
            return error.TestUnexpectedResult;
        };
        switch (term) {
            .signal, .exited => {},
            else => return error.TestUnexpectedResult,
        }
    }
}

test "raiseDefault restores SIG_DFL then terminates child with SIGINT" {
    if (comptime !is_posix) return error.SkipZigTest;

    if (comptime is_posix) {
        const rc = posix.system.fork();
        switch (posix.errno(rc)) {
            .SUCCESS => {},
            else => return error.SkipZigTest,
        }

        if (rc == 0) {
            sig.install() catch std.process.exit(2);
            sig.raiseDefault(posix.SIG.INT);
        }

        const child_pid: posix.pid_t = @intCast(rc);
        var status: i32 = 0;
        while (true) {
            const wr = posix.system.waitpid(child_pid, &status, 0);
            switch (posix.errno(wr)) {
                .SUCCESS => break,
                .INTR => continue,
                else => return error.TestUnexpectedResult,
            }
        }

        const st: u32 = @bitCast(status);
        if (posix.W.IFSIGNALED(st)) {
            try std.testing.expectEqual(posix.SIG.INT, posix.W.TERMSIG(st));
        } else if (posix.W.IFEXITED(st)) {
            try std.testing.expectEqual(@as(u8, 130), posix.W.EXITSTATUS(st));
        } else {
            return error.TestUnexpectedResult;
        }
    }
}

test "wakeFd is installed alongside handlers" {
    if (comptime !is_posix) return error.SkipZigTest;

    if (comptime is_posix) {
        try sig.install();
        defer sig.uninstall();
        try std.testing.expect(sig.wakeFd() != null);
    }
}

test "windows: install + uninstall + double install" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    try sig.install();
    defer sig.uninstall();
    try std.testing.expectError(error.AlreadyInstalled, sig.install());
    try std.testing.expect(sig.wakeFd() == null);
}
