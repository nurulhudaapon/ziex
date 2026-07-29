//! Playground / browser WASM entry for the ZX language server.
//!
//! Mirrors the export surface used by the Zigtools playground ZLS build:
//! https://github.com/zigtools/playground/blob/main/src/zls.zig
//!
//! `createServer` + `allocMessage` + `call` + `outputMessage*` so the editor
//! worker can drive our Handler without a blocking stdio `_start` loop.

comptime {
    @setEvalBranchQuota(100_000);
}

const std = @import("std");
const lsp = @import("lsp");
const Handler = @import("Handler.zig");

const allocator = std.heap.wasm_allocator;

pub const std_options: std.Options = .{
    .log_level = .warn,
};

var threaded: std.Io.Threaded = .init_single_threaded;

var transport: lsp.Transport = .{
    .vtable = &.{
        .readJsonMessage = readJsonMessage,
        .writeJsonMessage = writeJsonMessage,
    },
};

var handler: Handler = undefined;
var handler_alive = false;

var input_bytes: std.ArrayList(u8) = .empty;
var input_consumed = false;

var output_message_starts: std.ArrayList(usize) = .empty;
var output_message_bytes: std.ArrayList(u8) = .empty;

fn readJsonMessage(_: *lsp.Transport, _: std.Io, gpa: std.mem.Allocator) (std.mem.Allocator.Error || lsp.Transport.ReadError)![]u8 {
    if (input_consumed) return error.EndOfStream;
    input_consumed = true;
    return try gpa.dupe(u8, input_bytes.items);
}

fn writeJsonMessage(_: *lsp.Transport, _: std.Io, json_message: []const u8) lsp.Transport.WriteError!void {
    output_message_starts.append(allocator, output_message_bytes.items.len) catch return error.NoSpaceLeft;
    output_message_bytes.appendSlice(allocator, json_message) catch return error.NoSpaceLeft;
}

export fn createServer() void {
    if (handler_alive) {
        handler.deinit();
        handler_alive = false;
    }
    const io = threaded.io();
    handler = .init(allocator, &transport, io);
    handler_alive = true;
}

export fn allocMessage(len: usize) [*]u8 {
    input_bytes.clearRetainingCapacity();
    input_bytes.resize(allocator, len) catch @panic("OOM");
    return input_bytes.items.ptr;
}

export fn call() void {
    @setEvalBranchQuota(100_000);
    std.debug.assert(handler_alive);

    output_message_starts.clearRetainingCapacity();
    output_message_bytes.clearRetainingCapacity();
    input_consumed = false;

    const io = threaded.io();
    lsp.basic_server.run(
        io,
        allocator,
        &transport,
        &handler,
        null,
    ) catch |err| switch (err) {
        // One-shot transport: after the message is handled the next read ends the loop.
        error.EndOfStream => {},
        else => std.debug.panic("zx-lsp call failed: {s}", .{@errorName(err)}),
    };
}

export fn outputMessageCount() usize {
    return output_message_starts.items.len;
}

export fn outputMessagePtr(index: usize) [*]const u8 {
    return output_message_bytes.items[output_message_starts.items[index]..].ptr;
}

export fn outputMessageLen(index: usize) usize {
    const next_start = if (index + 1 < output_message_starts.items.len)
        output_message_starts.items[index + 1]
    else
        output_message_bytes.items.len;
    return next_start - output_message_starts.items[index];
}
