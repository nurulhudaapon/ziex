//! Structured zig dbuidld output parser for watch mode.
//!
//! zig --watch stderr output order per build cycle:
//!   1. [optional] `zig build-exe ...` — compilation started (change detected)
//!   2. `Build Summary: N/M steps succeeded; X failed` — outcome
//!   3. Build tree (+/- lines per step)
//!   4. Blank line
//!   5. Error diagnostics (if failed): `file:line:col: error: msg` blocks
//!   6. `error: the following command failed with N compilation errors:` — end of errors
//!
//! Events returned from processLine:
//!   change_detected  — a `zig build-exe/lib/obj` line seen → recompilation started
//!   should_restart   — binary mtime changed after a successful Build Summary
//!   errors           — structured diagnostics, emitted when the error block ends
//!   resolved         — previous build had errors, current succeeded
const std = @import("std");
const log = std.log.scoped(.builder);
const RESTART_COOLDOWN_NS = std.time.ns_per_ms * 10;

pub const DiagKind = enum { @"error", warning, note };

pub const Diagnostic = struct {
    file: []const u8,
    line: u32,
    col: u32,
    kind: DiagKind,
    message: []const u8,
    source_line: ?[]const u8 = null,
    caret_line: ?[]const u8 = null,
};

pub const BuildResult = struct {
    allocator: std.mem.Allocator,
    success: bool,
    diagnostics: []Diagnostic,

    pub fn deinit(self: *BuildResult) void {
        for (self.diagnostics) |d| {
            self.allocator.free(d.file);
            self.allocator.free(d.message);
            if (d.source_line) |sl| self.allocator.free(sl);
            if (d.caret_line) |cl| self.allocator.free(cl);
        }
        self.allocator.free(self.diagnostics);
    }
};

pub const Event = union(enum) {
    change_detected,
    should_restart: u64, // build_duration_ms
    errors: BuildResult,
    resolved,
    build_complete_no_change: u64, // build_duration_ms — successful build but binary unchanged
};

pub const BuildState = struct {
    allocator: std.mem.Allocator,
    binary_path: ?[]const u8,
    last_binary_mtime: i128,
    last_restart_time_ns: i128,
    first_build_done: bool,
    previous_had_errors: bool,

    // Per-cycle parse state
    diagnostics: std.ArrayList(Diagnostic),
    build_in_progress: bool,
    pending_has_errors: bool,
    max_duration_ms: u64,
    skip_next_build_cmd: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        binary_path: ?[]const u8,
        initial_mtime: i128,
    ) BuildState {
        return .{
            .allocator = allocator,
            .binary_path = binary_path,
            .last_binary_mtime = initial_mtime,
            .last_restart_time_ns = 0,
            .first_build_done = false,
            .previous_had_errors = false,
            .diagnostics = std.ArrayList(Diagnostic).empty,
            .build_in_progress = false,
            .pending_has_errors = false,
            .max_duration_ms = 0,
            .skip_next_build_cmd = false,
        };
    }

    pub fn deinit(self: *BuildState) void {
        for (self.diagnostics.items) |d| {
            self.allocator.free(d.file);
            self.allocator.free(d.message);
            if (d.source_line) |sl| self.allocator.free(sl);
            if (d.caret_line) |cl| self.allocator.free(cl);
        }
        self.diagnostics.deinit(self.allocator);
    }

    pub fn markRestartComplete(self: *BuildState, new_mtime: i128) void {
        self.last_restart_time_ns = std.time.nanoTimestamp();
        self.last_binary_mtime = new_mtime;
    }

    /// Process a single line of stderr output. Returns an event if one was triggered.
    pub fn processLine(self: *BuildState, line: []const u8) !?Event {
        log.debug("stderr: {s}", .{line});

        // End-of-error marker
        if (std.mem.startsWith(u8, line, "error: the following command failed")) {
            const event = self.emitErrors();
            self.pending_has_errors = false;
            self.skip_next_build_cmd = true;
            return event;
        }

        // zig build-exe/lib/obj: next compilation cycle starting
        if (isBuildCommand(line)) {
            if (self.skip_next_build_cmd) {
                self.skip_next_build_cmd = false;
                return null;
            }

            // Emit any errors accumulated from the PREVIOUS cycle.
            var event: ?Event = null;
            if (self.pending_has_errors and self.diagnostics.items.len > 0) {
                event = self.emitErrors();
            } else {
                freeDiagnostics(self.allocator, &self.diagnostics);
            }
            self.pending_has_errors = false;
            self.max_duration_ms = 0;
            self.build_in_progress = true;

            if (self.first_build_done) {
                // If we already have a pending error event, prefer returning that.
                // change_detected will be returned on the next relevant line.
                if (event != null) return event;
                log.debug("Change detected: compilation started", .{});
                return .change_detected;
            }
            return event;
        }

        self.skip_next_build_cmd = false;

        // Accumulate timing
        accumulateDuration(line, &self.max_duration_ms);

        // Try to parse as a structured diagnostic
        if (parseDiagnostic(self.allocator, line)) |diag| {
            if (diag.kind == .@"error") self.pending_has_errors = true;
            try self.diagnostics.append(self.allocator, diag);
            return null;
        }

        // Try to capture pinpoint context
        if (self.diagnostics.items.len > 0) {
            var last_diag = &self.diagnostics.items[self.diagnostics.items.len - 1];
            if (last_diag.source_line == null) {
                // The very first line after a diagnostic is the source line
                // UNLESS it's a command/summary line or a new diagnostic
                if (line.len > 0) {
                    last_diag.source_line = try self.allocator.dupe(u8, line);
                    return null;
                }
            } else if (last_diag.caret_line == null) {
                if (std.mem.indexOfAny(u8, line, "^~") != null) {
                    last_diag.caret_line = try self.allocator.dupe(u8, line);
                    return null;
                }
            }
        }

        // Build Summary
        if (std.mem.indexOf(u8, line, "Build Summary:") != null) {
            const succeeded = std.mem.indexOf(u8, line, "failed") == null;
            return self.handleBuildSummary(succeeded);
        }

        return null;
    }

    /// Flush any pending errors at EOF.
    pub fn flushPending(self: *BuildState) ?Event {
        if (self.pending_has_errors and self.diagnostics.items.len > 0) {
            return self.emitErrors();
        }
        return null;
    }

    fn handleBuildSummary(self: *BuildState, succeeded: bool) ?Event {
        const now = std.time.nanoTimestamp();
        log.debug("Build Summary, succeeded={}", .{succeeded});

        const binary_changed = if (self.binary_path) |path| blk: {
            const stat = std.fs.cwd().statFile(path) catch |err| {
                log.debug("stat failed: {s}", .{@errorName(err)});
                self.build_in_progress = false;
                return null;
            };
            break :blk stat.mtime != self.last_binary_mtime;
        } else false;

        if (!self.first_build_done) {
            self.first_build_done = true;
            if (self.binary_path) |path| {
                const stat = std.fs.cwd().statFile(path) catch null;
                if (stat) |s| self.last_binary_mtime = s.mtime;
            }
            self.last_restart_time_ns = now;
            self.previous_had_errors = !succeeded;
            log.debug("First build complete, binary_changed={}", .{binary_changed});
            self.build_in_progress = false;
            // Always treat the first success as a "ready" signal.
            if (succeeded) return .{ .should_restart = self.max_duration_ms };
            return null;
        }

        var event: ?Event = null;

        if (succeeded) {
            if (binary_changed or self.binary_path == null) {
                const elapsed = now - self.last_restart_time_ns;
                if (elapsed >= RESTART_COOLDOWN_NS) {
                    if (self.binary_path) |path| {
                        const stat = std.fs.cwd().statFile(path) catch null;
                        if (stat) |s| self.last_binary_mtime = s.mtime;
                    }
                    log.debug("Binary changed, restart triggered", .{});
                    event = .{ .should_restart = self.max_duration_ms };
                }
            } else if (!self.previous_had_errors) {
                event = .{ .build_complete_no_change = self.max_duration_ms };
            }
            if (self.previous_had_errors) {
                if (event == null) {
                    event = .resolved;
                }
            }
            self.previous_had_errors = false;
        } else {
            self.previous_had_errors = true;
        }

        self.build_in_progress = false;
        return event;
    }

    fn emitErrors(self: *BuildState) ?Event {
        log.debug("emitErrors: emitting {} diagnostics", .{self.diagnostics.items.len});

        const owned = self.diagnostics.toOwnedSlice(self.allocator) catch return null;

        self.pending_has_errors = false;
        return .{ .errors = .{
            .allocator = self.allocator,
            .success = false,
            .diagnostics = owned,
        } };
    }
};

// Formatting
pub fn formatDiagnostics(allocator: std.mem.Allocator, diagnostics: []const Diagnostic) ![]u8 {
    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(allocator);
    for (diagnostics) |d| {
        const kind_str: []const u8 = switch (d.kind) {
            .@"error" => "error",
            .warning => "warning",
            .note => "note",
        };
        const line = try std.fmt.allocPrint(allocator, "{s}:{d}:{d}: {s}: {s}\n", .{
            d.file, d.line, d.col, kind_str, d.message,
        });
        defer allocator.free(line);
        try buf.appendSlice(allocator, line);

        if (d.source_line) |sl| {
            try buf.appendSlice(allocator, sl);
            try buf.append(allocator, '\n');
        }
        if (d.caret_line) |cl| {
            try buf.appendSlice(allocator, cl);
            try buf.append(allocator, '\n');
        }
    }
    return buf.toOwnedSlice(allocator);
}

// Helpers
fn isBuildCommand(line: []const u8) bool {
    if (std.mem.indexOf(u8, line, "zig build-exe") != null) return true;
    if (std.mem.indexOf(u8, line, "zig build-lib") != null) return true;
    if (std.mem.indexOf(u8, line, "zig build-obj") != null) return true;
    return false;
}

fn freeDiagnostics(allocator: std.mem.Allocator, diagnostics: *std.ArrayList(Diagnostic)) void {
    for (diagnostics.items) |d| {
        allocator.free(d.file);
        allocator.free(d.message);
        if (d.source_line) |sl| allocator.free(sl);
        if (d.caret_line) |cl| allocator.free(cl);
    }
    diagnostics.clearRetainingCapacity();
}

/// Try to parse `file:line:col: kind: message`. Returns null if no match.
fn parseDiagnostic(allocator: std.mem.Allocator, line: []const u8) ?Diagnostic {
    const KindMatch = struct { kind: DiagKind, marker: []const u8 };
    const matches = [_]KindMatch{
        .{ .kind = .@"error", .marker = ": error: " },
        .{ .kind = .warning, .marker = ": warning: " },
        .{ .kind = .note, .marker = ": note: " },
    };

    var chosen_kind: DiagKind = undefined;
    var location_end: usize = 0;
    var msg_start: usize = 0;
    var found = false;
    for (matches) |m| {
        if (std.mem.indexOf(u8, line, m.marker)) |pos| {
            chosen_kind = m.kind;
            location_end = pos;
            msg_start = pos + m.marker.len;
            found = true;
            break;
        }
    }
    if (!found) return null;

    const location = line[0..location_end];
    const message = line[msg_start..];
    if (location.len == 0 or message.len == 0) return null;

    // Parse "file:LINE:COL" — find the last two colons.
    var last_colon: usize = 0;
    var prev_colon: usize = 0;
    var j: usize = 0;
    while (j < location.len) : (j += 1) {
        if (location[j] == ':') {
            prev_colon = last_colon;
            last_colon = j;
        }
    }
    if (last_colon == 0 or prev_colon == 0 or prev_colon >= last_colon) return null;

    const file_part = location[0..prev_colon];
    const line_str = location[prev_colon + 1 .. last_colon];
    const col_str = location[last_colon + 1 ..];

    if (file_part.len == 0) return null;
    const line_num = std.fmt.parseInt(u32, line_str, 10) catch return null;
    const col_num = std.fmt.parseInt(u32, col_str, 10) catch return null;

    const file_dup = allocator.dupe(u8, file_part) catch return null;
    const msg_dup = allocator.dupe(u8, message) catch {
        allocator.free(file_dup);
        return null;
    };

    return .{
        .file = file_dup,
        .line = line_num,
        .col = col_num,
        .kind = chosen_kind,
        .message = msg_dup,
    };
}

fn accumulateDuration(line: []const u8, max_ms: *u64) void {
    var it = std.mem.tokenizeAny(u8, line, " \t");
    while (it.next()) |tok| {
        if (parseDurationMs(tok)) |ms| {
            if (ms > max_ms.*) max_ms.* = ms;
        }
    }
}

fn parseDurationMs(text: []const u8) ?u64 {
    if (text.len < 2) return null;
    var num_end: usize = 0;
    while (num_end < text.len) : (num_end += 1) {
        const c = text[num_end];
        if (!std.ascii.isDigit(c) and c != '.') break;
    }
    if (num_end == 0) return null;
    const value = std.fmt.parseFloat(f64, text[0..num_end]) catch return null;
    const unit = text[num_end..];
    const ms: f64 = if (std.mem.eql(u8, unit, "s"))
        value * 1000.0
    else if (std.mem.eql(u8, unit, "ms"))
        value
    else if (std.mem.eql(u8, unit, "us") or std.mem.eql(u8, unit, "\xc2\xb5s"))
        value / 1000.0
    else if (std.mem.eql(u8, unit, "ns"))
        value / 1_000_000.0
    else if (std.mem.eql(u8, unit, "m"))
        value * 60_000.0
    else
        return null;
    return @intFromFloat(ms);
}

// Test fixtures
const err_sample = @embedFile("ErrorOutput.txt");
const sample = @embedFile("Output.txt");
const sampel_err_start_then_fix = @embedFile("ErrorThenFix.txt");

/// Feed a multi-line string through processLine, collecting events.
fn feedLines(state: *BuildState, input: []const u8, events: *std.ArrayList(Event)) !void {
    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |line| {
        const clean = if (line.len > 0 and line[line.len - 1] == '\r') line[0 .. line.len - 1] else line;
        if (try state.processLine(clean)) |event| {
            try events.append(state.allocator, event);
        }
    }
}

test "parseDiagnostic - errors" {
    const allocator = std.testing.allocator;

    const diag = parseDiagnostic(allocator, ".zig-cache/app/pages/page.zig:95:12: error: expected ',' after field").?;
    defer allocator.free(diag.file);
    defer allocator.free(diag.message);
    try std.testing.expectEqualStrings(".zig-cache/app/pages/page.zig", diag.file);
    try std.testing.expectEqual(@as(u32, 95), diag.line);
    try std.testing.expectEqual(@as(u32, 12), diag.col);
    try std.testing.expectEqual(DiagKind.@"error", diag.kind);
    try std.testing.expectEqualStrings("expected ',' after field", diag.message);
}

test "error build cycle emits errors" {
    const allocator = std.testing.allocator;

    var state = BuildState.init(allocator, "nonexistent", 0);
    state.first_build_done = true;
    defer state.deinit();

    var events = std.ArrayList(Event).empty;
    defer {
        for (events.items) |*e| {
            switch (e.*) {
                .errors => |*r| r.deinit(),
                else => {},
            }
        }
        events.deinit(allocator);
    }

    try feedLines(&state, err_sample, &events);

    // Find an errors event
    var found_errors = false;
    for (events.items) |*e| {
        switch (e.*) {
            .errors => |r| {
                try std.testing.expect(r.diagnostics.len > 0);
                try std.testing.expectEqual(false, r.success);
                found_errors = true;
            },
            else => {},
        }
    }
    try std.testing.expect(found_errors);
}

test "error then fix then error again: errors detected each time" {
    const allocator = std.testing.allocator;

    var state = BuildState.init(allocator, "nonexistent", 0);
    state.first_build_done = true;
    defer state.deinit();

    var events = std.ArrayList(Event).empty;
    defer {
        for (events.items) |*e| {
            switch (e.*) {
                .errors => |*r| r.deinit(),
                else => {},
            }
        }
        events.deinit(allocator);
    }

    // Phase 1: Error build
    try feedLines(&state, err_sample, &events);

    var error_count: usize = 0;
    for (events.items) |*e| {
        switch (e.*) {
            .errors => |r| {
                try std.testing.expect(r.diagnostics.len > 0);
                try std.testing.expectEqual(DiagKind.@"error", r.diagnostics[0].kind);
                error_count += 1;
            },
            else => {},
        }
    }
    try std.testing.expect(error_count > 0);

    // Phase 2: Simulate successful rebuild
    state.previous_had_errors = true;

    // Phase 3: Error comes back
    // Clear previous events
    for (events.items) |*e| {
        switch (e.*) {
            .errors => |*r| r.deinit(),
            else => {},
        }
    }
    events.clearRetainingCapacity();

    try feedLines(&state, err_sample, &events);

    var found_errors = false;
    for (events.items) |*e| {
        switch (e.*) {
            .errors => |r| {
                try std.testing.expect(r.diagnostics.len > 0);
                try std.testing.expectEqual(DiagKind.@"error", r.diagnostics[0].kind);
                found_errors = true;
            },
            else => {},
        }
    }
    try std.testing.expect(found_errors);
}

test "rebuild error detection with real watch output" {
    const allocator = std.testing.allocator;

    const tmp_path = "zig-out/.builder-test-bin";
    {
        var f = try std.fs.cwd().createFile(tmp_path, .{});
        f.close();
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const initial_stat = try std.fs.cwd().statFile(tmp_path);

    var state = BuildState.init(allocator, tmp_path, initial_stat.mtime);
    defer state.deinit();

    var events = std.ArrayList(Event).empty;
    defer {
        for (events.items) |*e| {
            switch (e.*) {
                .errors => |*r| r.deinit(),
                else => {},
            }
        }
        events.deinit(allocator);
    }

    try feedLines(&state, sampel_err_start_then_fix, &events);
    try std.testing.expect(state.first_build_done);

    // Clear events from phase 1
    for (events.items) |*e| {
        switch (e.*) {
            .errors => |*r| r.deinit(),
            else => {},
        }
    }
    events.clearRetainingCapacity();

    // Second error build
    try feedLines(&state, err_sample, &events);

    var found_errors = false;
    for (events.items) |*e| {
        switch (e.*) {
            .errors => |r| {
                try std.testing.expect(r.diagnostics.len > 0);
                try std.testing.expectEqual(DiagKind.@"error", r.diagnostics[0].kind);
                found_errors = true;
            },
            else => {},
        }
    }
    try std.testing.expect(found_errors);
}

test "full lifecycle: initial error build, fix, then error again" {
    const allocator = std.testing.allocator;

    const tmp_path = "zig-out/.builder-test-bin2";
    {
        var f = try std.fs.cwd().createFile(tmp_path, .{});
        f.close();
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const initial_stat = try std.fs.cwd().statFile(tmp_path);

    var state = BuildState.init(allocator, tmp_path, initial_stat.mtime);
    defer state.deinit();

    var events = std.ArrayList(Event).empty;
    defer {
        for (events.items) |*e| {
            switch (e.*) {
                .errors => |*r| r.deinit(),
                else => {},
            }
        }
        events.deinit(allocator);
    }

    // Phase 1: Initial error build
    try feedLines(&state, sampel_err_start_then_fix, &events);
    try std.testing.expect(state.first_build_done);

    // Clear events
    for (events.items) |*e| {
        switch (e.*) {
            .errors => |*r| r.deinit(),
            else => {},
        }
    }
    events.clearRetainingCapacity();

    // Phase 2: Error comes back
    try feedLines(&state, err_sample, &events);

    var found_errors = false;
    for (events.items) |*e| {
        switch (e.*) {
            .errors => |r| {
                try std.testing.expect(r.diagnostics.len > 0);
                try std.testing.expectEqualStrings("expected ',' after field", r.diagnostics[0].message);
                found_errors = true;
            },
            else => {},
        }
    }
    if (!found_errors) {
        std.debug.print("\nFAILED: no error events found!\n", .{});
        std.debug.print("  first_build_done={}\n", .{state.first_build_done});
        std.debug.print("  previous_had_errors={}\n", .{state.previous_had_errors});
        std.debug.print("  pending_has_errors={}\n", .{state.pending_has_errors});
        std.debug.print("  diagnostics.items.len={}\n", .{state.diagnostics.items.len});
        return error.TestUnexpectedResult;
    }
}

test "no false change_detected from error command path" {
    const allocator = std.testing.allocator;

    var state = BuildState.init(allocator, "nonexistent", 0);
    state.first_build_done = true;
    defer state.deinit();

    var events = std.ArrayList(Event).empty;
    defer {
        for (events.items) |*e| {
            switch (e.*) {
                .errors => |*r| r.deinit(),
                else => {},
            }
        }
        events.deinit(allocator);
    }

    try feedLines(&state, err_sample, &events);

    // Count change_detected events — should be exactly 1
    var change_count: usize = 0;
    for (events.items) |e| {
        switch (e) {
            .change_detected => change_count += 1,
            else => {},
        }
    }
    try std.testing.expectEqual(@as(usize, 1), change_count);
}

// Standalone main for manual testing
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Open log file for raw stderr capture
    var log_file = try std.fs.cwd().createFile("zig-out/build-stderr.log", .{});
    defer log_file.close();

    var child = std.process.Child.init(
        &.{ "zig", "build", "--watch", "--verbose", "--summary", "all" },
        allocator,
    );
    child.cwd = "./bench/ziex";
    child.stderr_behavior = .Pipe;
    child.stdout_behavior = .Pipe;

    try child.spawn();
    defer _ = child.kill() catch {};

    // Use a dummy binary path — we just want to see events
    var state = BuildState.init(allocator, "zig-out/bin/app", 0);
    state.first_build_done = true;
    defer state.deinit();

    const stderr = child.stderr.?;
    var raw_buf: [8192]u8 = undefined;
    var streaming_reader = stderr.readerStreaming(&raw_buf);
    const io_reader = &streaming_reader.interface;
    var line_writer = std.Io.Writer.Allocating.init(allocator);
    defer line_writer.deinit();

    while (io_reader.streamDelimiter(&line_writer.writer, '\n')) |_| {
        const line = line_writer.written();
        _ = io_reader.takeByte() catch break;

        // Write raw line to log file
        // log_file.writer().print("{s}\n", .{line}) catch {};

        // Show first 10 chars of each line for debugging
        const LINEN = 80;
        std.debug.print("Line: {s}\n", .{if (line.len > LINEN) line[0..LINEN] else line});

        // Process through BuildState
        if (state.processLine(line) catch null) |event| {
            switch (event) {
                .change_detected => {
                    std.debug.print("[EVENT] change_detected\n", .{});
                },
                .should_restart => |build_ms| {
                    std.debug.print("[EVENT] should_restart build_duration_ms={d}\n", .{build_ms});
                },
                .errors => |result| {
                    std.debug.print("[EVENT] errors count={d}\n", .{result.diagnostics.len});
                    for (result.diagnostics) |d| {
                        const kind_str: []const u8 = switch (d.kind) {
                            .@"error" => "error",
                            .warning => "warning",
                            .note => "note",
                        };
                        std.debug.print("  File: F-{s}:L{d}:C{d}: K{s}: M-{s}\n", .{ d.file, d.line, d.col, kind_str, d.message });
                    }
                    var r = result;
                    r.deinit();
                },
                .resolved => {
                    std.debug.print("[EVENT] resolved\n", .{});
                },
                .build_complete_no_change => |build_ms| {
                    std.debug.print("[EVENT] build_complete_no_change build_duration_ms={d}\n", .{build_ms});
                },
            }
        }

        line_writer.clearRetainingCapacity();
    } else |err| {
        if (err != error.EndOfStream) return err;
    }

    // Flush any pending
    if (state.flushPending()) |event| {
        switch (event) {
            .errors => |result| {
                std.debug.print("[EVENT] errors (flush) count={d}\n", .{result.diagnostics.len});
                var r = result;
                r.deinit();
            },
            else => {},
        }
    }

    std.debug.print("\n[DONE] Raw stderr saved to zig-out/build-stderr.log\n", .{});
}

pub const std_options: std.Options = .{
    .log_level = .info,
};
