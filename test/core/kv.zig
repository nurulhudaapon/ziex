const std = @import("std");
const zx = @import("zx");

const kv = zx.kv;

fn uniqueLabel(comptime prefix: []const u8, buf: []u8) ![]const u8 {
    const value = std.crypto.random.int(u64);
    return std.fmt.bufPrint(buf, "{s}-{x}", .{ prefix, value });
}

test "kv default impl: put/get/delete roundtrip" {
    var key_buf: [64]u8 = undefined;
    const key = try uniqueLabel("kv-default-key", &key_buf);
    const value = "hello from kv";

    defer kv.delete(key) catch {};

    try kv.put(key, value, .{});

    const found = (try kv.get(std.testing.allocator, key)).?;
    defer std.testing.allocator.free(found);

    try std.testing.expectEqualStrings(value, found);

    try kv.delete(key);
    try std.testing.expect((try kv.get(std.testing.allocator, key)) == null);
}

test "kv default impl: list returns prefixed keys" {
    var prefix_buf: [64]u8 = undefined;
    const prefix = try uniqueLabel("kv-list-prefix", &prefix_buf);

    var key1_buf: [96]u8 = undefined;
    var key2_buf: [96]u8 = undefined;
    var other_key_buf: [96]u8 = undefined;

    const key1 = try std.fmt.bufPrint(&key1_buf, "{s}-a", .{prefix});
    const key2 = try std.fmt.bufPrint(&key2_buf, "{s}-b", .{prefix});
    const other_key = try uniqueLabel("kv-list-other", &other_key_buf);

    defer kv.delete(key1) catch {};
    defer kv.delete(key2) catch {};
    defer kv.delete(other_key) catch {};

    try kv.put(key1, "value-a", .{});
    try kv.put(key2, "value-b", .{});
    try kv.put(other_key, "value-c", .{});

    const keys = try kv.list(std.testing.allocator, prefix);
    defer {
        for (keys) |key| std.testing.allocator.free(key);
        std.testing.allocator.free(keys);
    }

    var saw_key1 = false;
    var saw_key2 = false;
    for (keys) |key| {
        try std.testing.expect(std.mem.startsWith(u8, key, prefix));
        if (std.mem.eql(u8, key, key1)) saw_key1 = true;
        if (std.mem.eql(u8, key, key2)) saw_key2 = true;
        try std.testing.expect(!std.mem.eql(u8, key, other_key));
    }

    try std.testing.expect(saw_key1);
    try std.testing.expect(saw_key2);
}

test "kv default impl: scoped namespaces are isolated" {
    var ns_buf: [64]u8 = undefined;
    const namespace = try uniqueLabel("kv-scope", &ns_buf);

    const scoped = kv.scope(namespace);
    const key = "shared-key";

    defer scoped.delete(key) catch {};
    defer kv.delete(key) catch {};

    try scoped.put(key, "scoped-value", .{});
    try kv.put(key, "default-value", .{});

    const scoped_value = (try scoped.get(std.testing.allocator, key)).?;
    defer std.testing.allocator.free(scoped_value);

    const default_value = (try kv.get(std.testing.allocator, key)).?;
    defer std.testing.allocator.free(default_value);

    try std.testing.expectEqualStrings("scoped-value", scoped_value);
    try std.testing.expectEqualStrings("default-value", default_value);
}
