const std = @import("std");
const kv = @import("../../core/kv.zig");
const ext = @import("extern.zig");

fn get(_: *anyopaque, ns: []const u8, allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
    var buf: [8192]u8 = undefined;
    const n = ext.kv_get(ns.ptr, ns.len, key.ptr, key.len, &buf, buf.len);
    if (n < 0) return null;
    return try allocator.dupe(u8, buf[0..@intCast(n)]);
}

fn put(_: *anyopaque, ns: []const u8, key: []const u8, value: []const u8, _: kv.PutOptions) !void {
    if (ext.kv_put(ns.ptr, ns.len, key.ptr, key.len, value.ptr, value.len) < 0) return error.KvPutFailed;
}

fn delete(_: *anyopaque, ns: []const u8, key: []const u8) !void {
    if (ext.kv_delete(ns.ptr, ns.len, key.ptr, key.len) < 0) return error.KvDeleteFailed;
}

fn list(_: *anyopaque, ns: []const u8, allocator: std.mem.Allocator, prefix: []const u8) ![][]u8 {
    var buf: [65536]u8 = undefined;
    const n = ext.kv_list(ns.ptr, ns.len, prefix.ptr, prefix.len, &buf, buf.len);
    if (n <= 0) return &[_][]u8{};
    const parsed = try std.json.parseFromSlice([][]const u8, allocator, buf[0..@intCast(n)], .{});
    defer parsed.deinit();
    const keys = try allocator.alloc([]u8, parsed.value.len);
    for (parsed.value, 0..) |k, i| keys[i] = try allocator.dupe(u8, k);
    return keys;
}

pub const vtable = kv.VTable{
    .get = &get,
    .put = &put,
    .delete = &delete,
    .list = &list,
};

var _ctx: u8 = 0;

pub fn use() void {
    kv.adapter(@ptrCast(&_ctx), &vtable);
}
