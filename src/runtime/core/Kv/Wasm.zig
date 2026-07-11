const Wasm = @This();

const std = @import("std");
const Kv = @import("../Kv.zig");

const max_response_bytes = 16 * 1024 * 1024;

fn get(_: ?*anyopaque, ns: []const u8, allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
    var capacity: usize = 65536;
    var buf = try allocator.alloc(u8, capacity);
    defer allocator.free(buf);

    while (true) {
        const n = ext.kv_get(ns.ptr, ns.len, key.ptr, key.len, buf.ptr, capacity);
        if (n == -2) {
            capacity *= 2;
            if (capacity > max_response_bytes) return error.InvalidResponse;
            buf = try allocator.realloc(buf, capacity);
            continue;
        }
        if (n < 0) return null;
        return try allocator.dupe(u8, buf[0..@intCast(n)]);
    }
}

fn put(_: ?*anyopaque, ns: []const u8, key: []const u8, value: []const u8, opts: Kv.PutOptions) !void {
    const ttl: u32 = if (opts.ttl) |d| blk: {
        const secs = d.toSeconds();
        break :blk if (secs <= 0) 0 else @intCast(secs);
    } else 0;
    if (ext.kv_put(ns.ptr, ns.len, key.ptr, key.len, value.ptr, value.len, ttl) < 0) return error.KvPutFailed;
}

fn delete(_: ?*anyopaque, ns: []const u8, key: []const u8) !void {
    if (ext.kv_delete(ns.ptr, ns.len, key.ptr, key.len) < 0) return error.KvDeleteFailed;
}

fn list(_: ?*anyopaque, ns: []const u8, allocator: std.mem.Allocator, prefix: []const u8) ![][]u8 {
    var buf: [65536]u8 = undefined;
    const n = ext.kv_list(ns.ptr, ns.len, prefix.ptr, prefix.len, &buf, buf.len);
    if (n <= 0) return &[_][]u8{};
    const parsed = try std.json.parseFromSlice([][]const u8, allocator, buf[0..@intCast(n)], .{});
    defer parsed.deinit();
    const keys = try allocator.alloc([]u8, parsed.value.len);
    for (parsed.value, 0..) |k, i| keys[i] = try allocator.dupe(u8, k);
    return keys;
}

const ext = struct {
    pub extern "__zx_kv" fn kv_get(
        ns_ptr: [*]const u8,
        ns_len: usize,
        key_ptr: [*]const u8,
        key_len: usize,
        buf_ptr: [*]u8,
        buf_max: usize,
    ) i32;

    pub extern "__zx_kv" fn kv_put(
        ns_ptr: [*]const u8,
        ns_len: usize,
        key_ptr: [*]const u8,
        key_len: usize,
        val_ptr: [*]const u8,
        val_len: usize,
        ttl_seconds: u32,
    ) i32;

    pub extern "__zx_kv" fn kv_delete(
        ns_ptr: [*]const u8,
        ns_len: usize,
        key_ptr: [*]const u8,
        key_len: usize,
    ) i32;

    pub extern "__zx_kv" fn kv_list(
        ns_ptr: [*]const u8,
        ns_len: usize,
        prefix_ptr: [*]const u8,
        prefix_len: usize,
        buf_ptr: [*]u8,
        buf_max: usize,
    ) i32;
};

pub fn kv(wasm: *Wasm) Kv {
    return .{
        .userdata = wasm,
        .vtable = &.{
            .get = &get,
            .put = &put,
            .delete = &delete,
            .list = &list,
        },
    };
}
