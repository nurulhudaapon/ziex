const con = @This();

const std = @import("std");

const Handle = std.Io.net.Socket.Handle;
const empty_slot = std.math.maxInt(usize);

slots: [128]std.atomic.Value(usize) = @splat(.init(empty_slot)),

pub const Token = struct {
    index: usize,
    handle: usize,
};

pub fn track(self: *con, stream: std.Io.net.Stream) ?Token {
    const handle = encode(stream.socket.handle);
    for (&self.slots, 0..) |*slot, index| {
        if (slot.cmpxchgStrong(empty_slot, handle, .acq_rel, .acquire) == null) {
            return .{ .index = index, .handle = handle };
        }
    }
    return null;
}

pub fn untrack(self: *con, token: Token) void {
    _ = self.slots[token.index].cmpxchgStrong(token.handle, empty_slot, .acq_rel, .acquire);
}

pub fn shutdownAll(self: *con, io: std.Io) void {
    for (&self.slots) |*slot| {
        const encoded = slot.swap(empty_slot, .acq_rel);
        if (encoded == empty_slot) continue;
        const stream: std.Io.net.Stream = .{
            .socket = .{
                .handle = decode(encoded),
                .address = undefined,
            },
        };
        stream.shutdown(io, .both) catch {};
    }
}

fn encode(handle: Handle) usize {
    return switch (@typeInfo(Handle)) {
        .pointer => @intFromPtr(handle),
        .int => @intCast(handle),
        else => @compileError("unsupported network socket handle type"),
    };
}

fn decode(value: usize) Handle {
    return switch (@typeInfo(Handle)) {
        .pointer => @ptrFromInt(value),
        .int => @intCast(value),
        else => @compileError("unsupported network socket handle type"),
    };
}
