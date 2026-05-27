//! Structured zig build --watch output parser for dev mode.
//!
//! Each watch cycle's stderr looks roughly like:
//!
//!   <zig build-exe/-lib/-obj ...>            (compilation commands)
//!   <install -C ...>                          (install lines)
//!   Build Summary: N/M steps succeeded[; X failed]
//!   <tree of step results, each line ending in: success | cached | (reused) | <N errors> | transitive failure | ...>
//!   <blank line>
//!   [error: the following command failed ...]   (on failure)
//!
//! The "success" vs "cached" suffix in the tree is the ground truth for whether
//! an install step actually produced new output. We restart the running app iff
//! the tree contains an `install server <name> success` or
//! `install client <name> success` line. Anything else (all cached, transitive
//! failure, etc.) is a no-op. This is far more reliable than the previous
//! approach of stat'ing the binary/wasm mtimes - 0.16 reprints all `install -C`
//! lines every cycle even for cached assets, and a `.zx` edit may rebuild the
//! wasm without changing the server binary.
//!
//! Events emitted (consumed by src/cli/dev.zig):
//!   change_detected             - a new compilation cycle started
//!   should_restart              - tree says a server/client install succeeded
//!   build_complete_no_change    - tree says every install was cached
//!   assets_installed            - tree says `install app/assets/` or `install app/public/` succeeded
//!   errors                      - parsed diagnostics for a failed cycle
//!   resolved                    - previous cycle had errors, current cycle succeeded
const std = @import("std");
const builtin = @import("builtin");
const log = std.log.scoped(.builder);

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
            if (d.file.len > 0) self.allocator.free(d.file);
            if (d.message.len > 0) self.allocator.free(d.message);
            if (d.source_line) |sl| self.allocator.free(sl);
            if (d.caret_line) |cl| self.allocator.free(cl);
        }
        self.allocator.free(self.diagnostics);
    }
};

pub const AssetChange = struct {
    allocator: std.mem.Allocator,
    files: []const []const u8, // web-relative paths like "/favicon.ico", "/assets/styles.css"
    build_duration_ms: u64,

    pub fn deinit(self: *AssetChange) void {
        for (self.files) |f| self.allocator.free(f);
        self.allocator.free(self.files);
    }
};

pub const Event = union(enum) {
    change_detected,
    should_restart: u64,
    errors: BuildResult,
    resolved,
    build_complete_no_change: u64,
    assets_installed: AssetChange,
};

const StepStatus = enum { success, cached, failure };

pub const BuildState = struct {
    allocator: std.mem.Allocator,
    os_tag: std.Target.Os.Tag,
    first_build_done: bool,
    previous_had_errors: bool,

    diagnostics: std.ArrayList(Diagnostic),
    pending_has_errors: bool,
    max_duration_ms: u64,
    in_summary_tree: bool,
    server_status: ?StepStatus,
    client_status: ?StepStatus,
    user_assets_changed: bool,
    pending_asset_paths: std.ArrayList([]const u8),
    skip_next_build_cmd: bool,

    pub fn init(allocator: std.mem.Allocator) BuildState {
        return .{
            .allocator = allocator,
            .os_tag = builtin.os.tag,
            .first_build_done = false,
            .previous_had_errors = false,
            .diagnostics = std.ArrayList(Diagnostic).empty,
            .pending_has_errors = false,
            .max_duration_ms = 0,
            .in_summary_tree = false,
            .server_status = null,
            .client_status = null,
            .user_assets_changed = false,
            .pending_asset_paths = std.ArrayList([]const u8).empty,
            .skip_next_build_cmd = false,
        };
    }

    pub fn deinit(self: *BuildState) void {
        freeDiagnostics(self.allocator, &self.diagnostics);
        self.diagnostics.deinit(self.allocator);
        self.clearPendingAssets();
        self.pending_asset_paths.deinit(self.allocator);
    }

    /// Process a single line of stderr output. Returns an event if one is
    /// triggered by this specific line.
    pub fn processLine(self: *BuildState, line: []const u8) !?Event {
        log.debug("stderr: {s}", .{line});

        if (std.mem.startsWith(u8, line, "error: the following command failed")) {
            const event = self.flushPendingErrors();
            self.skip_next_build_cmd = true;
            return event;
        }

        // `zig build-exe/lib/obj` line: a fresh cycle is starting. Anything
        // accumulated belongs to the previous cycle.
        if (isBuildCommandForOs(self.os_tag, line)) {
            if (self.skip_next_build_cmd) {
                self.skip_next_build_cmd = false;
                return null;
            }

            const event = self.resetForNewCycle();
            if (self.first_build_done) {
                if (event != null) return event;
                log.debug("change_detected", .{});
                return .change_detected;
            }
            return event;
        }
        self.skip_next_build_cmd = false;

        if (self.in_summary_tree) {
            if (line.len == 0) {
                return self.finalizeCycle();
            }
            self.parseTreeLine(line);
            accumulateDuration(line, &self.max_duration_ms);
            return null;
        }

        if (parseUserAssetInstall(line)) |asset| {
            const web_path = std.fmt.allocPrint(self.allocator, "/{s}", .{asset.web_path}) catch null;
            if (web_path) |wp| {
                self.pending_asset_paths.append(self.allocator, wp) catch self.allocator.free(wp);
            }
        }

        accumulateDuration(line, &self.max_duration_ms);

        if (parseDiagnostic(self.allocator, line)) |diag| {
            if (diag.kind == .@"error") self.pending_has_errors = true;
            try self.diagnostics.append(self.allocator, diag);
            return null;
        }

        if (self.diagnostics.items.len > 0) {
            var last_diag = &self.diagnostics.items[self.diagnostics.items.len - 1];
            if (last_diag.source_line == null) {
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

        if (std.mem.indexOf(u8, line, "Build Summary:") != null) {
            self.in_summary_tree = true;
            return null;
        }

        return null;
    }

    pub fn flushPending(self: *BuildState) ?Event {
        return self.flushPendingErrors();
    }

    fn finalizeCycle(self: *BuildState) ?Event {
        self.in_summary_tree = false;

        if (self.pending_has_errors and self.diagnostics.items.len > 0) {
            return self.flushPendingErrors();
        }

        const had_failure = (self.server_status orelse .cached) == .failure or
            (self.client_status orelse .cached) == .failure;
        if (had_failure) {
            self.previous_had_errors = true;
            return null;
        }

        const restart = (self.server_status orelse .cached) == .success or
            (self.client_status orelse .cached) == .success;

        if (!self.first_build_done) {
            self.first_build_done = true;
            self.previous_had_errors = false;
            return .{ .should_restart = self.max_duration_ms };
        }

        if (restart) {
            const was_in_error = self.previous_had_errors;
            self.previous_had_errors = false;
            _ = was_in_error;
            return .{ .should_restart = self.max_duration_ms };
        }

        if (self.user_assets_changed and self.pending_asset_paths.items.len > 0) {
            const files = self.pending_asset_paths.toOwnedSlice(self.allocator) catch blk: {
                self.clearPendingAssets();
                break :blk &.{};
            };
            const duration = self.max_duration_ms;
            if (self.previous_had_errors) self.previous_had_errors = false;
            return .{ .assets_installed = .{
                .allocator = self.allocator,
                .files = files,
                .build_duration_ms = duration,
            } };
        }

        if (self.previous_had_errors) {
            self.previous_had_errors = false;
            return .resolved;
        }

        return .{ .build_complete_no_change = self.max_duration_ms };
    }

    fn resetForNewCycle(self: *BuildState) ?Event {
        var event: ?Event = null;
        if (self.pending_has_errors and self.diagnostics.items.len > 0) {
            event = self.flushPendingErrors();
        } else {
            freeDiagnostics(self.allocator, &self.diagnostics);
        }
        self.pending_has_errors = false;
        self.max_duration_ms = 0;
        self.in_summary_tree = false;
        self.server_status = null;
        self.client_status = null;
        self.user_assets_changed = false;
        self.clearPendingAssets();
        return event;
    }

    fn parseTreeLine(self: *BuildState, line: []const u8) void {
        // Strip leading tree decoration (│├└─| +-) and any whitespace. Each
        // platform/zig version draws the tree slightly differently:
        //   0.16 macOS/Linux: "│  └─ install server ..."
        //   0.16 windows:     "|  +- install server ..."
        const content = stripTreePrefix(line);
        if (content.len == 0) return;

        // The summary may include ANSI dim codes for the install role even
        // when colour is "off" - e.g. "install \x1b[2mserver\x1b[0m ziex_app
        // success" or its escape-stripped variant "install [2mserver[0m ...".
        const cleaned = stripAnsiInPlace(content);

        if (parseInstallStatus(cleaned, "server")) |status| {
            self.server_status = mergeStatus(self.server_status, status);
            return;
        }
        if (parseInstallStatus(cleaned, "client")) |status| {
            self.client_status = mergeStatus(self.client_status, status);
            return;
        }

        // Pre-0.16 trees: the role was inferred from the line below, where the
        // leaf says `compile exe <name> Debug native` (server) vs
        // `compile exe <name> Debug wasm32-freestanding-none` (client). To
        // keep the new parser simple we also accept the wasm leaf as proof
        // that the client step status applied to it.
        if (parseCompileStatus(cleaned, "native")) |status| {
            // A `compile exe <name> Debug native success` line in the OUTER
            // install branch (without a sibling install client line) means
            // server. We can't always disambiguate; conservatively treat it
            // as the server unless a client_status is already set higher.
            if (self.server_status == null) self.server_status = status;
            return;
        }
        if (parseCompileStatus(cleaned, "wasm32-freestanding-none")) |status| {
            if (self.client_status == null) self.client_status = status;
            return;
        }

        // User-asset directory installs (`install app/assets/ success`,
        // `install app/public/ cached`).
        if (parseAssetDirStatus(cleaned)) |status| {
            if (status == .success) self.user_assets_changed = true;
            return;
        }
    }

    fn flushPendingErrors(self: *BuildState) ?Event {
        if (self.diagnostics.items.len == 0) {
            self.pending_has_errors = false;
            return null;
        }
        const owned = self.diagnostics.toOwnedSlice(self.allocator) catch return null;
        self.pending_has_errors = false;
        self.previous_had_errors = true;
        // A failing cycle never makes it to a clean tree finalize; ensure we
        // don't carry stale tree state into the next cycle.
        self.in_summary_tree = false;
        return .{ .errors = .{
            .allocator = self.allocator,
            .success = false,
            .diagnostics = owned,
        } };
    }

    fn clearPendingAssets(self: *BuildState) void {
        for (self.pending_asset_paths.items) |p| self.allocator.free(p);
        self.pending_asset_paths.clearRetainingCapacity();
    }
};

/// If both status observations differ, the "more successful" one wins. A
/// build tree may show both `install server X success` and a transitive
/// `install server X cached` on different branches; we want `success`.
fn mergeStatus(prev: ?StepStatus, next: StepStatus) StepStatus {
    const p = prev orelse return next;
    if (p == .success or next == .success) return .success;
    if (p == .failure or next == .failure) return .failure;
    return .cached;
}

fn stripTreePrefix(line: []const u8) []const u8 {
    var i: usize = 0;
    while (i < line.len) {
        const c = line[i];
        // ASCII tree drawing chars.
        if (c == ' ' or c == '\t' or c == '|' or c == '+' or c == '-') {
            i += 1;
            continue;
        }
        // UTF-8 box-drawing prefixes: ─ │ ├ └ ┌ ┐ ┘ etc. all start with 0xE2 0x94 or 0xE2 0x95.
        if (c == 0xE2 and i + 2 < line.len and (line[i + 1] == 0x94 or line[i + 1] == 0x95)) {
            i += 3;
            continue;
        }
        break;
    }
    return std.mem.trim(u8, line[i..], " \t");
}

/// Remove inline ANSI escape sequences and "bare" CSI fragments like "[2m" /
/// "[0m" left behind when the escape byte was stripped upstream. The result
/// reuses the input buffer (returning a sub-slice up to the new length).
fn stripAnsiInPlace(line: []const u8) []const u8 {
    // ANSI cleanup is rare; do it lazily with a scratch trick: rewrite into a
    // small stack buffer only when needed.
    var has_ansi = false;
    for (line) |b| {
        if (b == 0x1B or b == '[') {
            has_ansi = true;
            break;
        }
    }
    if (!has_ansi) return line;

    // Single-pass strip. Output is at most input length, so it's safe to
    // operate on a local static buffer for the typical tree-line length.
    var buf: [512]u8 = undefined;
    var out_len: usize = 0;
    var i: usize = 0;
    while (i < line.len and out_len < buf.len) {
        const c = line[i];
        if (c == 0x1B) {
            // Skip ESC + '[' + ... + final byte in 0x40..0x7E.
            i += 1;
            if (i < line.len and line[i] == '[') i += 1;
            while (i < line.len) : (i += 1) {
                const b = line[i];
                if (b >= 0x40 and b <= 0x7E) {
                    i += 1;
                    break;
                }
            }
            continue;
        }
        if (c == '[') {
            // Bare CSI-like fragment? Only strip if it looks like "[<digits>m".
            var j = i + 1;
            while (j < line.len and std.ascii.isDigit(line[j])) : (j += 1) {}
            if (j > i + 1 and j < line.len and line[j] == 'm') {
                i = j + 1;
                continue;
            }
        }
        buf[out_len] = c;
        out_len += 1;
        i += 1;
    }
    return buf[0..out_len];
}

/// Match `install <role> <name> <status>` (status is the final word, possibly
/// followed by timing info we ignore). Returns the status or null.
fn parseInstallStatus(content: []const u8, role: []const u8) ?StepStatus {
    const prefix = "install ";
    if (!std.mem.startsWith(u8, content, prefix)) return null;
    var rest = content[prefix.len..];

    if (!std.mem.startsWith(u8, rest, role)) return null;
    rest = rest[role.len..];
    if (rest.len == 0 or rest[0] != ' ') return null;
    rest = std.mem.trimStart(u8, rest, " ");

    // Skip the `<name>` token.
    const space = std.mem.indexOfScalar(u8, rest, ' ') orelse return null;
    rest = std.mem.trimStart(u8, rest[space..], " ");
    return parseStatusWord(rest);
}

/// Match `compile <kind> <name> Debug <target> <status>`, e.g.
/// `compile exe main Debug wasm32-freestanding-none success`.
fn parseCompileStatus(content: []const u8, target_marker: []const u8) ?StepStatus {
    const prefix = "compile ";
    if (!std.mem.startsWith(u8, content, prefix)) return null;
    const marker_idx = std.mem.indexOf(u8, content, target_marker) orelse return null;
    var rest = content[marker_idx + target_marker.len ..];
    rest = std.mem.trimStart(u8, rest, " ");
    return parseStatusWord(rest);
}

/// Match `install <something>/ <status>` for asset directories.
fn parseAssetDirStatus(content: []const u8) ?StepStatus {
    const prefix = "install ";
    if (!std.mem.startsWith(u8, content, prefix)) return null;
    var rest = content[prefix.len..];
    const space = std.mem.indexOfScalar(u8, rest, ' ') orelse return null;
    const path = rest[0..space];
    if (path.len < 2 or path[path.len - 1] != '/') return null;
    rest = std.mem.trimStart(u8, rest[space..], " ");
    return parseStatusWord(rest);
}

/// The first token of `rest` is the status word. We ignore "(reused)" entirely
/// (it represents a downstream dependency dedupe, not a real install outcome).
fn parseStatusWord(rest: []const u8) ?StepStatus {
    if (rest.len == 0) return null;
    const end = std.mem.indexOfAny(u8, rest, " \t") orelse rest.len;
    const word = rest[0..end];
    if (std.mem.eql(u8, word, "success")) return .success;
    if (std.mem.eql(u8, word, "cached")) return .cached;
    // "1 errors", "2 errors", "transitive failure" - all mean failed.
    if (std.mem.endsWith(u8, rest, " errors") or
        std.mem.indexOf(u8, rest, "transitive failure") != null or
        std.mem.indexOf(u8, rest, "failure") != null)
    {
        return .failure;
    }
    return null;
}

const AssetInstall = struct {
    web_path: []const u8,
};

/// Parse `install -C <src> <dst>` for genuine user assets (anything under
/// `/static/` whose source is in `public/` or `assets/`). Returns the web path
/// (e.g. "favicon.ico" or "assets/style.css"). Built artifacts in
/// `.zig-cache` / package cache are filtered out.
fn parseUserAssetInstall(line: []const u8) ?AssetInstall {
    const trimmed = std.mem.trimStart(u8, line, " \t");
    if (!std.mem.startsWith(u8, trimmed, "install ")) return null;
    if (std.mem.indexOf(u8, trimmed, ".zig-cache") != null) return null;
    if (std.mem.indexOf(u8, trimmed, "/zig/p/") != null) return null;
    if (std.mem.indexOf(u8, trimmed, "/public/") == null and
        std.mem.indexOf(u8, trimmed, "/assets/") == null) return null;

    const static_marker = "/static/";
    const last_static_pos = std.mem.lastIndexOf(u8, trimmed, static_marker) orelse return null;
    const start = last_static_pos + static_marker.len;
    if (start >= trimmed.len) return null;
    return .{ .web_path = trimmed[start..] };
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

fn isBuildCommandLine(line: []const u8) bool {
    return isBuildCommandForOs(builtin.os.tag, line);
}

fn isBuildCommandForOs(os_tag: std.Target.Os.Tag, line: []const u8) bool {
    const trimmed = std.mem.trim(u8, line, " \t");
    if (trimmed.len == 0) return false;

    const exe, const rest = nextCommandToken(trimmed) orelse return false;
    const subcommand, _ = nextCommandToken(rest) orelse return false;

    const exe_name = switch (os_tag) {
        .windows => commandBasenameWindows(exe),
        else => std.fs.path.basename(exe),
    };
    const expected_exe_name = switch (os_tag) {
        .windows => "zig.exe",
        else => "zig",
    };
    if (!std.mem.eql(u8, exe_name, expected_exe_name)) return false;

    return std.mem.eql(u8, subcommand, "build-exe") or
        std.mem.eql(u8, subcommand, "build-lib") or
        std.mem.eql(u8, subcommand, "build-obj");
}

fn nextCommandToken(input: []const u8) ?struct { []const u8, []const u8 } {
    const trimmed = std.mem.trimStart(u8, input, " \t");
    if (trimmed.len == 0) return null;
    if (trimmed[0] == '"') {
        const end = std.mem.indexOfScalarPos(u8, trimmed, 1, '"') orelse return null;
        return .{ trimmed[1..end], trimmed[end + 1 ..] };
    }
    const end = std.mem.indexOfAny(u8, trimmed, " \t") orelse trimmed.len;
    return .{ trimmed[0..end], trimmed[end..] };
}

fn commandBasenameWindows(path: []const u8) []const u8 {
    const idx = std.mem.lastIndexOfAny(u8, path, "/\\") orelse return path;
    return path[idx + 1 ..];
}

/// Try to parse `file:line:col: kind: message`. Returns null if no match.
pub fn parseDiagnostic(allocator: std.mem.Allocator, line: []const u8) ?Diagnostic {
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

const err_sample = @embedFile("ErrorOutput.txt");
const sample_win = @embedFile("Output_Win.txt");
const sample_err_then_fix = @embedFile("ErrorThenFix.txt");
const sample_first = @embedFile("FirstOutput.txt");
const sample_change = @embedFile("ChangeOutput.txt");

fn feedLines(state: *BuildState, input: []const u8, events: *std.ArrayList(Event)) !void {
    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |line| {
        const clean = if (line.len > 0 and line[line.len - 1] == '\r') line[0 .. line.len - 1] else line;
        if (try state.processLine(clean)) |event| {
            try events.append(state.allocator, event);
        }
    }
    if (state.flushPending()) |event| {
        try events.append(state.allocator, event);
    }
}

fn freeEvents(allocator: std.mem.Allocator, events: *std.ArrayList(Event)) void {
    for (events.items) |*e| switch (e.*) {
        .errors => |*r| r.deinit(),
        .assets_installed => |*a| a.deinit(),
        else => {},
    };
    events.deinit(allocator);
}

test "parseStatusWord recognizes success/cached/failure" {
    try std.testing.expectEqual(StepStatus.success, parseStatusWord("success 35s MaxRSS:964M").?);
    try std.testing.expectEqual(StepStatus.cached, parseStatusWord("cached 102ms MaxRSS:32M").?);
    try std.testing.expectEqual(StepStatus.failure, parseStatusWord("1 errors").?);
    try std.testing.expectEqual(StepStatus.failure, parseStatusWord("transitive failure").?);
    try std.testing.expectEqual(@as(?StepStatus, null), parseStatusWord("(reused)"));
}

test "parseInstallStatus parses server/client lines" {
    try std.testing.expectEqual(StepStatus.success, parseInstallStatus("install server ziex_app success 35s", "server").?);
    try std.testing.expectEqual(StepStatus.cached, parseInstallStatus("install server ziex_app cached 102ms", "server").?);
    try std.testing.expectEqual(StepStatus.success, parseInstallStatus("install client ziex_app success", "client").?);
    try std.testing.expectEqual(@as(?StepStatus, null), parseInstallStatus("install ziex_app success", "server"));
}

test "stripTreePrefix handles unicode and ascii trees" {
    try std.testing.expectEqualStrings("install server x success", stripTreePrefix("│  └─ install server x success"));
    try std.testing.expectEqualStrings("install server x success", stripTreePrefix("|  +- install server x success"));
    try std.testing.expectEqualStrings("install x success", stripTreePrefix("├─ install x success"));
}

test "stripAnsiInPlace removes dim codes" {
    const out = stripAnsiInPlace("install [2mserver[0m ziex_app success");
    try std.testing.expectEqualStrings("install server ziex_app success", out);
}

test "FirstOutput.txt: first cycle is success, second is cached" {
    const allocator = std.testing.allocator;
    var state = BuildState.init(allocator);
    defer state.deinit();

    var events = std.ArrayList(Event).empty;
    defer freeEvents(allocator, &events);

    try feedLines(&state, sample_first, &events);

    // Cycle 1: should_restart (first build done).
    // Cycle 2: build_complete_no_change (everything cached) - but FirstOutput
    // doesn't terminate cycle 2's tree with a blank line; the stream just ends.
    // We don't require the second event, but the first must be a restart.
    var found_restart = false;
    for (events.items) |e| {
        if (e == .should_restart) {
            found_restart = true;
            break;
        }
    }
    try std.testing.expect(found_restart);
}

test "FirstOutput.txt: second cycle is no-change (all cached)" {
    const allocator = std.testing.allocator;
    var state = BuildState.init(allocator);
    defer state.deinit();

    var events = std.ArrayList(Event).empty;
    defer freeEvents(allocator, &events);

    // Append a trailing blank line so the second tree finalizes.
    const padded = try std.mem.concat(allocator, u8, &.{ sample_first, "\n\n" });
    defer allocator.free(padded);

    try feedLines(&state, padded, &events);

    var restart_count: usize = 0;
    var no_change_count: usize = 0;
    for (events.items) |e| switch (e) {
        .should_restart => restart_count += 1,
        .build_complete_no_change => no_change_count += 1,
        else => {},
    };
    try std.testing.expectEqual(@as(usize, 1), restart_count);
    try std.testing.expectEqual(@as(usize, 1), no_change_count);
}

test "ChangeOutput.txt: server+client success triggers should_restart" {
    const allocator = std.testing.allocator;
    var state = BuildState.init(allocator);
    state.first_build_done = true;
    defer state.deinit();

    var events = std.ArrayList(Event).empty;
    defer freeEvents(allocator, &events);

    // Trailing blank to finalize the tree.
    const padded = try std.mem.concat(allocator, u8, &.{ sample_change, "\n\n" });
    defer allocator.free(padded);

    try feedLines(&state, padded, &events);

    var found_restart = false;
    var found_no_change = false;
    for (events.items) |e| switch (e) {
        .should_restart => found_restart = true,
        .build_complete_no_change => found_no_change = true,
        else => {},
    };
    try std.testing.expect(found_restart);
    try std.testing.expect(!found_no_change);
}

test "synthetic: all-cached tree emits no_change, not restart" {
    const allocator = std.testing.allocator;
    var state = BuildState.init(allocator);
    state.first_build_done = true;
    defer state.deinit();

    var events = std.ArrayList(Event).empty;
    defer freeEvents(allocator, &events);

    const input =
        "/usr/bin/zig build-exe -ODebug --name x\n" ++
        "install -C .zig-cache/o/abc/main.wasm /proj/zig-out/static/assets/_/main.wasm\n" ++
        "install -C .zig-cache/o/abc/ziex_app /proj/zig-out/bin/ziex_app\n" ++
        "Build Summary: 32/32 steps succeeded\n" ++
        "install cached\n" ++
        "├─ install ziex_app cached\n" ++
        "│  └─ install server ziex_app cached 102ms MaxRSS:32M\n" ++
        "└─ install client ziex_app cached\n" ++
        "   └─ compile exe main Debug wasm32-freestanding-none cached 80ms\n" ++
        "\n";

    try feedLines(&state, input, &events);

    var found_restart = false;
    var found_no_change = false;
    for (events.items) |e| switch (e) {
        .should_restart => found_restart = true,
        .build_complete_no_change => found_no_change = true,
        else => {},
    };
    try std.testing.expect(!found_restart);
    try std.testing.expect(found_no_change);
}

test "synthetic: server success only (zx edit rebuilds server)" {
    const allocator = std.testing.allocator;
    var state = BuildState.init(allocator);
    state.first_build_done = true;
    defer state.deinit();

    var events = std.ArrayList(Event).empty;
    defer freeEvents(allocator, &events);

    const input =
        "/usr/bin/zig build-exe -ODebug --name x\n" ++
        "Build Summary: 32/32 steps succeeded\n" ++
        "install success\n" ++
        "├─ install ziex_app success\n" ++
        "│  └─ install server ziex_app success 5s MaxRSS:680M\n" ++
        "└─ install client ziex_app cached\n" ++
        "\n";

    try feedLines(&state, input, &events);

    var found_restart = false;
    for (events.items) |e| if (e == .should_restart) {
        found_restart = true;
    };
    try std.testing.expect(found_restart);
}

test "synthetic: client success only (zx edit rebuilds wasm)" {
    const allocator = std.testing.allocator;
    var state = BuildState.init(allocator);
    state.first_build_done = true;
    defer state.deinit();

    var events = std.ArrayList(Event).empty;
    defer freeEvents(allocator, &events);

    const input =
        "/usr/bin/zig build-exe -ODebug --name x\n" ++
        "Build Summary: 32/32 steps succeeded\n" ++
        "install success\n" ++
        "├─ install ziex_app success\n" ++
        "│  └─ install server ziex_app cached 102ms\n" ++
        "└─ install client ziex_app success 928ms\n" ++
        "\n";

    try feedLines(&state, input, &events);

    var found_restart = false;
    var found_no_change = false;
    for (events.items) |e| switch (e) {
        .should_restart => found_restart = true,
        .build_complete_no_change => found_no_change = true,
        else => {},
    };
    try std.testing.expect(found_restart);
    try std.testing.expect(!found_no_change);
}

test "synthetic: asset-only change emits assets_installed" {
    const allocator = std.testing.allocator;
    var state = BuildState.init(allocator);
    state.first_build_done = true;
    defer state.deinit();

    var events = std.ArrayList(Event).empty;
    defer freeEvents(allocator, &events);

    const input =
        "/usr/bin/zig build-exe -ODebug --name x\n" ++
        "install -C /proj/app/assets/style.css /proj/zig-out/static/assets/style.css\n" ++
        "Build Summary: 32/32 steps succeeded\n" ++
        "install success\n" ++
        "├─ install ziex_app cached\n" ++
        "│  └─ install server ziex_app cached 102ms\n" ++
        "│     ├─ install app/assets/ success\n" ++
        "└─ install client ziex_app cached\n" ++
        "\n";

    try feedLines(&state, input, &events);

    var found_assets = false;
    var found_restart = false;
    for (events.items) |e| switch (e) {
        .assets_installed => |a| {
            try std.testing.expect(a.files.len >= 1);
            found_assets = true;
        },
        .should_restart => found_restart = true,
        else => {},
    };
    try std.testing.expect(found_assets);
    try std.testing.expect(!found_restart);
}

test "error build cycle emits errors" {
    const allocator = std.testing.allocator;
    var state = BuildState.init(allocator);
    state.first_build_done = true;
    defer state.deinit();

    var events = std.ArrayList(Event).empty;
    defer freeEvents(allocator, &events);

    try feedLines(&state, err_sample, &events);

    var found_errors = false;
    for (events.items) |*e| switch (e.*) {
        .errors => |r| {
            try std.testing.expect(r.diagnostics.len > 0);
            try std.testing.expectEqualStrings("expected ',' after field", r.diagnostics[0].message);
            try std.testing.expectEqual(DiagKind.@"error", r.diagnostics[0].kind);
            found_errors = true;
        },
        else => {},
    };
    try std.testing.expect(found_errors);
}

test "error then fix: error event then later resolved" {
    const allocator = std.testing.allocator;
    var state = BuildState.init(allocator);
    state.first_build_done = true;
    defer state.deinit();

    var events = std.ArrayList(Event).empty;
    defer freeEvents(allocator, &events);

    try feedLines(&state, sample_err_then_fix, &events);

    var saw_error = false;
    var saw_restart_or_resolved = false;
    for (events.items) |e| switch (e) {
        .errors => saw_error = true,
        .should_restart, .resolved => saw_restart_or_resolved = true,
        else => {},
    };
    try std.testing.expect(saw_error);
    try std.testing.expect(saw_restart_or_resolved);
}

test "windows watch output detects build start and restart" {
    const allocator = std.testing.allocator;
    var state = BuildState.init(allocator);
    state.os_tag = .windows;
    state.first_build_done = true;
    defer state.deinit();

    var events = std.ArrayList(Event).empty;
    defer freeEvents(allocator, &events);

    // Pad with a trailing blank line to finalize the tree.
    const padded = try std.mem.concat(allocator, u8, &.{ sample_win, "\n\n" });
    defer allocator.free(padded);

    try feedLines(&state, padded, &events);

    // Output_Win.txt is two cycles glued together with the summary tree of
    // the FIRST cycle showing all-cached, then a new build-exe starts cycle 2.
    var change_count: usize = 0;
    for (events.items) |e| if (e == .change_detected) {
        change_count += 1;
    };
    try std.testing.expect(change_count >= 1);
}

test "parseDiagnostic - errors" {
    const allocator = std.testing.allocator;
    const diag = parseDiagnostic(allocator, ".zig-cache/app/pages/page.zig:95:12: error: expected ',' after field").?;
    defer allocator.free(diag.file);
    defer allocator.free(diag.message);
    try std.testing.expectEqualStrings(".zig-cache/app/pages/page.zig", diag.file);
    try std.testing.expectEqual(@as(u32, 95), diag.line);
    try std.testing.expectEqual(@as(u32, 12), diag.col);
}

test "isBuildCommand handles windows zig path and rejects other tools" {
    try std.testing.expect(isBuildCommandForOs(.windows, "\"C:\\\\Users\\\\x\\\\zig.exe\" build-exe -ODebug"));
    try std.testing.expect(isBuildCommandForOs(.macos, "/Users/x/.asdf/installs/zig/0.16.0/zig build-lib -ODebug"));
    try std.testing.expect(!isBuildCommandForOs(.windows, "install -C foo bar"));
}

test "parseDurationMs handles common units" {
    try std.testing.expectEqual(@as(?u64, 23), parseDurationMs("23ms"));
    try std.testing.expectEqual(@as(?u64, 1500), parseDurationMs("1.5s"));
    try std.testing.expectEqual(@as(?u64, null), parseDurationMs("cached"));
}

test "parseUserAssetInstall extracts web path" {
    const a = parseUserAssetInstall("install -C /proj/app/public/favicon.ico /proj/zig-out/static/favicon.ico").?;
    try std.testing.expectEqualStrings("favicon.ico", a.web_path);
    try std.testing.expect(parseUserAssetInstall("install -C .zig-cache/o/abc/main.wasm /proj/zig-out/static/assets/_/main.wasm") == null);
}
