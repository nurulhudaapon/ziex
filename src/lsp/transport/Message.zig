const std = @import("std");
const builtin = @import("builtin");
const lsp = @import("lsp");
const Handler = @import("../Handler.zig");

const gpa = if (builtin.os.tag == .wasi or builtin.os.tag == .freestanding)
    std.heap.wasm_allocator
else
    std.heap.page_allocator;

const Message = @This();

threaded: std.Io.Threaded = .init_single_threaded,
transport: lsp.Transport = .{
    .vtable = &.{
        .readJsonMessage = readJsonMessage,
        .writeJsonMessage = writeJsonMessage,
    },
},
handler: Handler = undefined,
handler_alive: bool = false,

input_bytes: std.ArrayList(u8) = .empty,
input_consumed: bool = false,

output_message_starts: std.ArrayList(usize) = .empty,
output_message_bytes: std.ArrayList(u8) = .empty,

var global_session: Message = .{};

fn readJsonMessage(_: *lsp.Transport, _: std.Io, allocator: std.mem.Allocator) (std.mem.Allocator.Error || lsp.Transport.ReadError)![]u8 {
    const self = &global_session;
    if (self.input_consumed) return error.EndOfStream;
    self.input_consumed = true;
    return try allocator.dupe(u8, self.input_bytes.items);
}

fn writeJsonMessage(_: *lsp.Transport, _: std.Io, json_message: []const u8) lsp.Transport.WriteError!void {
    const self = &global_session;
    self.output_message_starts.append(gpa, self.output_message_bytes.items.len) catch return error.NoSpaceLeft;
    self.output_message_bytes.appendSlice(gpa, json_message) catch return error.NoSpaceLeft;
}

pub fn get() *Message {
    return &global_session;
}

pub fn ensure(self: *Message) void {
    if (self.handler_alive) return;
    const io = self.threaded.io();
    self.handler = .init(gpa, &self.transport, io);
    self.handler_alive = true;
}

pub fn reset(self: *Message) void {
    if (self.handler_alive) {
        self.handler.deinit();
        self.handler_alive = false;
    }
    self.input_bytes.clearRetainingCapacity();
    self.output_message_starts.clearRetainingCapacity();
    self.output_message_bytes.clearRetainingCapacity();
    self.input_consumed = false;
}

pub fn setInput(self: *Message, message: []const u8) !void {
    self.input_bytes.clearRetainingCapacity();
    try self.input_bytes.appendSlice(gpa, message);
    self.input_consumed = false;
}

pub fn clearOutput(self: *Message) void {
    self.output_message_starts.clearRetainingCapacity();
    self.output_message_bytes.clearRetainingCapacity();
}

pub fn outputCount(self: *const Message) usize {
    return self.output_message_starts.items.len;
}

pub fn outputSlice(self: *const Message, index: usize) []const u8 {
    const start = self.output_message_starts.items[index];
    const end = if (index + 1 < self.output_message_starts.items.len)
        self.output_message_starts.items[index + 1]
    else
        self.output_message_bytes.items.len;
    return self.output_message_bytes.items[start..end];
}

pub fn dispatch(self: *Message, message: []const u8) !void {
    @setEvalBranchQuota(100_000);
    self.ensure();
    self.clearOutput();
    try self.setInput(message);

    const io = self.threaded.io();
    lsp.basic_server.run(
        io,
        gpa,
        &self.transport,
        &self.handler,
        null,
    ) catch |err| switch (err) {
        error.EndOfStream => {},
        else => return err,
    };
}

pub fn runMessages(messages: []const []const u8, writer: *std.Io.Writer) !void {
    const self = get();
    self.reset();
    defer self.reset();

    for (messages) |message| {
        try self.dispatch(message);
        for (0..self.outputCount()) |i| {
            try writer.writeAll(self.outputSlice(i));
            try writer.writeByte('\n');
        }
    }
}

comptime {
    if (builtin.os.tag == .wasi or builtin.os.tag == .freestanding) {
        @export(&createServer, .{ .name = "createServer" });
        @export(&allocMessage, .{ .name = "allocMessage" });
        @export(&call, .{ .name = "call" });
        @export(&outputMessageCount, .{ .name = "outputMessageCount" });
        @export(&outputMessagePtr, .{ .name = "outputMessagePtr" });
        @export(&outputMessageLen, .{ .name = "outputMessageLen" });
    }
}

fn createServer() callconv(.c) void {
    const self = get();
    self.reset();
    self.ensure();
}

fn allocMessage(len: usize) callconv(.c) [*]u8 {
    const self = get();
    self.input_bytes.clearRetainingCapacity();
    self.input_bytes.resize(gpa, len) catch @panic("OOM");
    return self.input_bytes.items.ptr;
}

fn call() callconv(.c) void {
    @setEvalBranchQuota(100_000);
    const self = get();
    std.debug.assert(self.handler_alive);

    self.clearOutput();
    self.input_consumed = false;

    const io = self.threaded.io();
    lsp.basic_server.run(
        io,
        gpa,
        &self.transport,
        &self.handler,
        null,
    ) catch |err| switch (err) {
        error.EndOfStream => {},
        else => std.debug.panic("zx lsp call failed: {s}", .{@errorName(err)}),
    };
}

fn outputMessageCount() callconv(.c) usize {
    return get().outputCount();
}

fn outputMessagePtr(index: usize) callconv(.c) [*]const u8 {
    return get().outputSlice(index).ptr;
}

fn outputMessageLen(index: usize) callconv(.c) usize {
    return get().outputSlice(index).len;
}
