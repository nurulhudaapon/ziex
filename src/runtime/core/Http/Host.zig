//! JS-backed `Io.Writer` for Wasm/edge responses.
//! `drain`/`flush` forward bytes via `__zx_http.write`.
const Host = @This();

const std = @import("std");
const ext = @import("../../server/wasm/extern.zig");
const Conn = @import("Conn.zig");

buf: [4096]u8 = undefined,
writer: std.Io.Writer = undefined,

pub fn init(self: *Host) void {
    self.writer = .{
        .buffer = &self.buf,
        .vtable = &vtable,
    };
}

const vtable: std.Io.Writer.VTable = .{
    .drain = drain,
    .flush = flush,
};

fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
    if (w.end > 0) {
        ext.http_write(w.buffer[0..w.end].ptr, w.end);
        w.end = 0;
    }
    for (data[0 .. data.len - 1]) |slice| {
        if (slice.len > 0) ext.http_write(slice.ptr, slice.len);
    }
    const pattern = data[data.len - 1];
    var i: usize = 0;
    while (i < splat) : (i += 1) {
        if (pattern.len > 0) ext.http_write(pattern.ptr, pattern.len);
    }
    return std.Io.Writer.countSplat(data, splat);
}

fn flush(w: *std.Io.Writer) std.Io.Writer.Error!void {
    if (w.end == 0) return;
    ext.http_write(w.buffer[0..w.end].ptr, w.end);
    w.end = 0;
}

/// Commit status/headers to the host before the first body byte.
pub fn commit(allocator: std.mem.Allocator, conn: *const Conn, streaming: bool) !void {
    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();
    try writeMetaJson(&aw.writer, conn, streaming);
    const meta = aw.written();
    ext.http_commit(conn.status, meta.ptr, meta.len);
}

pub fn end() void {
    ext.http_end();
}

fn writeMetaJson(writer: *std.Io.Writer, conn: *const Conn, streaming: bool) !void {
    try writer.writeAll("{\"streaming\":");
    try writer.writeAll(if (streaming) "true" else "false");
    try writer.writeAll(",\"headers\":[");
    for (conn.resp_headers.items, 0..) |entry, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.writeAll("[");
        try writeJsonString(writer, entry.name);
        try writer.writeAll(",");
        try writeJsonString(writer, entry.value);
        try writer.writeAll("]");
    }
    try writer.writeAll("]}");
}

fn writeJsonString(writer: *std.Io.Writer, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try writer.print("\\u{x:0>4}", .{c});
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
    try writer.writeByte('"');
}
