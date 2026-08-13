const RunnerOutput = @This();

const std = @import("std");

const Io = std.Io;

state: *State,
thread: std.Thread,

const State = struct {
    io: Io,
    allocator: std.mem.Allocator,
    stdout: Io.File,
    stderr: Io.File,
    mutex: Io.Mutex = .init,
    first_line: ?[]u8 = null,
    first_line_captured: std.atomic.Value(bool) = .init(false),
    main_done_waiting: bool = false,
    main_claimed_first_line: bool = false,
    first_line_forwarded: bool = false,
    done: std.atomic.Value(bool) = .init(false),
};

pub fn init(
    io: Io,
    allocator: std.mem.Allocator,
    child: *const std.process.Child,
) !RunnerOutput {
    const state = try allocator.create(State);
    errdefer allocator.destroy(state);
    state.* = .{
        .io = io,
        .allocator = allocator,
        .stdout = child.stdout.?,
        .stderr = child.stderr.?,
    };
    return .{
        .state = state,
        .thread = try std.Thread.spawn(.{}, run, .{state}),
    };
}

pub fn waitForFirstLine(self: *const RunnerOutput, timeout_ms: u64) bool {
    var elapsed_ms: u64 = 0;
    while (!self.state.first_line_captured.load(.acquire) and
        !self.state.done.load(.acquire) and
        elapsed_ms < timeout_ms)
    {
        self.state.io.sleep(.fromMilliseconds(1), .awake) catch {};
        elapsed_ms += 1;
    }

    const captured = self.state.first_line_captured.load(.acquire);
    self.state.mutex.lockUncancelable(self.state.io);
    self.state.main_done_waiting = true;
    self.state.main_claimed_first_line = captured;
    self.state.mutex.unlock(self.state.io);
    return captured;
}

pub fn consumeFirstLine(self: *RunnerOutput) ?[]const u8 {
    self.state.mutex.lockUncancelable(self.state.io);
    defer self.state.mutex.unlock(self.state.io);
    if (!self.state.main_claimed_first_line or self.state.first_line_forwarded) return null;
    self.state.first_line_forwarded = true;
    return self.state.first_line;
}

pub fn wait(self: *const RunnerOutput) void {
    while (!self.state.done.load(.acquire)) {
        self.state.io.sleep(.fromMilliseconds(1), .awake) catch {};
    }
}

pub fn deinit(self: *RunnerOutput) void {
    self.thread.join();
    if (self.state.first_line) |line| self.state.allocator.free(line);
    self.state.allocator.destroy(self.state);
    self.* = undefined;
}

fn run(state: *State) void {
    defer state.done.store(true, .release);

    var streams_buffer: Io.File.MultiReader.Buffer(2) = undefined;
    var multi_reader: Io.File.MultiReader = undefined;
    multi_reader.init(
        state.allocator,
        state.io,
        streams_buffer.toStreams(),
        &.{ state.stderr, state.stdout },
    );
    defer multi_reader.deinit();

    const stderr = multi_reader.reader(0);
    const stdout = multi_reader.reader(1);

    while (true) {
        drainStdout(state, stdout);
        drainStderr(state, stderr, false);
        multi_reader.fill(1, .none) catch |err| switch (err) {
            error.EndOfStream => break,
            else => {
                std.log.debug("runner output read failed: {any}", .{err});
                break;
            },
        };
    }

    drainStdout(state, stdout);
    drainStderr(state, stderr, true);
    multi_reader.checkAnyError() catch |err| {
        if (err != error.Canceled) std.log.debug("runner output stream failed: {any}", .{err});
    };
}

fn drainStdout(state: *State, reader: *Io.Reader) void {
    const bytes = reader.buffered();
    if (bytes.len == 0) return;
    Io.File.stdout().writeStreamingAll(state.io, bytes) catch {};
    reader.toss(bytes.len);
}

fn drainStderr(state: *State, reader: *Io.Reader, final: bool) void {
    if (!state.first_line_captured.load(.acquire)) {
        const bytes = reader.buffered();
        const newline = std.mem.indexOfScalar(u8, bytes, '\n');
        if (newline == null and !final) return;
        if (newline == null and bytes.len == 0) return;

        const consumed_len = if (newline) |index| index + 1 else bytes.len;
        var line = bytes[0 .. consumed_len - @intFromBool(newline != null)];
        if (line.len > 0 and line[line.len - 1] == '\r') line.len -= 1;
        const owned = state.allocator.dupe(u8, line) catch return;
        reader.toss(consumed_len);

        state.mutex.lockUncancelable(state.io);
        state.first_line = owned;
        state.first_line_captured.store(true, .release);
        state.mutex.unlock(state.io);

        while (true) {
            state.mutex.lockUncancelable(state.io);
            const done_waiting = state.main_done_waiting;
            if (done_waiting and !state.main_claimed_first_line and !state.first_line_forwarded) {
                Io.File.stderr().writeStreamingAll(state.io, owned) catch {};
                Io.File.stderr().writeStreamingAll(state.io, "\n") catch {};
                state.first_line_forwarded = true;
            }
            state.mutex.unlock(state.io);
            if (done_waiting) break;
            state.io.sleep(.fromMilliseconds(1), .awake) catch {};
        }
    }

    const bytes = reader.buffered();
    if (bytes.len == 0) return;
    Io.File.stderr().writeStreamingAll(state.io, bytes) catch {};
    reader.toss(bytes.len);
}
