//! LSP proxy for ZX files.
//!
//! Spawns `zls` as a subprocess and sits between the editor and zls,
//! filtering LSP messages that cause false errors on valid ZX syntax.
//!
//! Usage: zxls <path-to-zls> [zls-args...]

const std = @import("std");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try std.fs.File.stderr().writeAll("usage: zxls <zls> [args...]\n");
        std.process.exit(2);
    }

    var child = std.process.Child.init(args[1..], allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Inherit;
    try child.spawn();

    // Thread: forward editor stdin -> zls stdin (unmodified)
    const forward_thread = try std.Thread.spawn(.{}, forwardRaw, .{
        std.fs.File.stdin(),
        child.stdin.?,
    });

    // Main: read zls stdout, filter diagnostics, write to editor stdout
    filterOutput(allocator, child.stdout.?) catch {};

    forward_thread.join();
    _ = try child.wait();
}

/// Copies bytes from `in` to `out` without interpretation.
fn forwardRaw(in: std.fs.File, out: std.fs.File) void {
    var buf: [8192]u8 = undefined;
    while (true) {
        const n = in.read(&buf) catch break;
        if (n == 0) break;
        out.writeAll(buf[0..n]) catch break;
    }
}

fn filterOutput(allocator: std.mem.Allocator, child_stdout: std.fs.File) !void {
    const reader = child_stdout.deprecatedReader();
    const stdout = std.fs.File.stdout();

    while (true) {
        const body = readLspMessage(allocator, reader) catch break orelse break;
        defer allocator.free(body);

        // Try to filter; on any error (not a diagnostics message, nothing to
        // filter, parse failure) fall back to sending the original body.
        const filtered = tryFilterDiagnostics(allocator, body) catch null;
        defer if (filtered) |f| allocator.free(f);

        writeLspMessage(stdout, filtered orelse body) catch break;
    }
}

fn readLspMessage(allocator: std.mem.Allocator, reader: anytype) !?[]u8 {
    var content_length: usize = 0;

    // Read headers until blank line
    while (true) {
        var line_buf: [256]u8 = undefined;
        const line = reader.readUntilDelimiter(&line_buf, '\n') catch |e| switch (e) {
            error.EndOfStream => return null,
            else => return e,
        };
        const trimmed = std.mem.trimRight(u8, line, "\r");
        if (trimmed.len == 0) break;
        if (std.mem.startsWith(u8, trimmed, "Content-Length: ")) {
            content_length = try std.fmt.parseInt(usize, trimmed["Content-Length: ".len..], 10);
        }
    }

    if (content_length == 0) return try allocator.dupe(u8, "");
    const body = try allocator.alloc(u8, content_length);
    errdefer allocator.free(body);
    try reader.readNoEof(body);
    return body;
}

fn writeLspMessage(file: std.fs.File, body: []const u8) !void {
    var header_buf: [64]u8 = undefined;
    const header = try std.fmt.bufPrint(&header_buf, "Content-Length: {d}\r\n\r\n", .{body.len});
    try file.writeAll(header);
    try file.writeAll(body);
}

/// Returns a newly allocated filtered message, or an error if no filtering
/// was needed or possible (caller should use the original body in that case).
fn tryFilterDiagnostics(allocator: std.mem.Allocator, body: []const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{ .allocate = .alloc_always });
    defer parsed.deinit();

    // Must be an object with method == "textDocument/publishDiagnostics"
    const root_obj = switch (parsed.value) {
        .object => |*o| o,
        else => return error.NotObject,
    };
    const method_val = root_obj.get("method") orelse return error.NoMethod;
    const method = switch (method_val) {
        .string => |s| s,
        else => return error.NotString,
    };
    if (!std.mem.eql(u8, method, "textDocument/publishDiagnostics")) return error.NotDiagnostics;

    // Navigate to params.diagnostics
    const params_ptr = root_obj.getPtr("params") orelse return error.NoParams;
    const params_obj = switch (params_ptr.*) {
        .object => |*o| o,
        else => return error.NotObject,
    };
    const diags_ptr = params_obj.getPtr("diagnostics") orelse return error.NoDiagnostics;
    const diags_arr = switch (diags_ptr.*) {
        .array => |*a| a,
        else => return error.NotArray,
    };

    // Remove matching diagnostics in place
    var i: usize = 0;
    var removed: usize = 0;
    while (i < diags_arr.items.len) {
        if (shouldFilter(diags_arr.items[i])) {
            _ = diags_arr.orderedRemove(i);
            removed += 1;
        } else {
            i += 1;
        }
    }

    if (removed == 0) return error.NothingFiltered;

    var aw: std.io.Writer.Allocating = .init(allocator);
    errdefer aw.deinit();
    try std.json.Stringify.value(parsed.value, .{}, &aw.writer);
    return aw.toOwnedSlice();
}

fn shouldFilter(value: std.json.Value) bool {
    const obj = switch (value) {
        .object => |o| o,
        else => return false,
    };
    const msg_val = obj.get("message") orelse return false;
    const msg = switch (msg_val) {
        .string => |s| s,
        else => return false,
    };
    return std.mem.indexOf(u8, msg, "expected expression, found '<'") != null;
}
