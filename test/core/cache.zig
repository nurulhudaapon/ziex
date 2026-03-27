const std = @import("std");
const zx = @import("zx");

const cache = zx.cache;
const allocator = std.testing.allocator;

const Profile = struct {
    id: u32,
    name: []const u8,
    active: bool,
};

const ProfileAlias = struct {
    id: u32,
    label: []const u8,
    active: bool,
};

const WorkerContext = struct {
    ns: []const u8,
    worker_id: usize,
    err: ?anyerror = null,
};

fn ensureCache() !void {
    try cache.init(std.heap.page_allocator, .{
        .max_size = 4096,
        .segment_count = 8,
    });
}

fn uniqueLabel(comptime prefix: []const u8, buf: []u8) ![]const u8 {
    const value = std.crypto.random.int(u64);
    return std.fmt.bufPrint(buf, "{s}-{x}", .{ prefix, value });
}

fn freeProfile(profile: Profile) void {
    allocator.free(profile.name);
}

test "cache: put/get/delete roundtrip" {
    try ensureCache();
    defer cache.deinit();

    var key_buf: [96]u8 = undefined;
    const key = try uniqueLabel("cache-roundtrip", &key_buf);

    defer cache.delete(key) catch {};

    try cache.put(key, "cached value", .{ .expiration_ttl = 30 });

    const found = (try cache.get(allocator, key)).?;
    defer allocator.free(found);

    try std.testing.expectEqualStrings("cached value", found);

    try cache.delete(key);
    try std.testing.expect((try cache.get(allocator, key)) == null);
}

test "cache: del reports whether key existed" {
    try ensureCache();
    defer cache.deinit();

    var key_buf: [96]u8 = undefined;
    const key = try uniqueLabel("cache-del", &key_buf);

    try std.testing.expect(!cache.del(key));

    try cache.put(key, "delete me", .{ .expiration_ttl = 30 });
    try std.testing.expect(cache.del(key));
    try std.testing.expect(!cache.del(key));
}

test "cache: list and delPrefix work for live entries" {
    try ensureCache();
    defer cache.deinit();

    var prefix_buf: [96]u8 = undefined;
    const prefix = try uniqueLabel("cache-prefix", &prefix_buf);

    var key1_buf: [128]u8 = undefined;
    var key2_buf: [128]u8 = undefined;
    var other_key_buf: [128]u8 = undefined;

    const key1 = try std.fmt.bufPrint(&key1_buf, "{s}-a", .{prefix});
    const key2 = try std.fmt.bufPrint(&key2_buf, "{s}-b", .{prefix});
    const other_key = try uniqueLabel("cache-other", &other_key_buf);

    defer _ = cache.delPrefix(prefix);
    defer cache.delete(other_key) catch {};

    try cache.put(key1, "value-a", .{ .expiration_ttl = 30 });
    try cache.put(key2, "value-b", .{ .expiration_ttl = 30 });
    try cache.put(other_key, "value-c", .{ .expiration_ttl = 30 });

    const keys = try cache.list(allocator, prefix);
    defer {
        for (keys) |key| allocator.free(key);
        allocator.free(keys);
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
    try std.testing.expectEqual(@as(usize, 2), try cache.scope("default").delPrefix(prefix));
    try std.testing.expect((try cache.get(allocator, key1)) == null);
    try std.testing.expect((try cache.get(allocator, key2)) == null);
}

test "cache: scoped namespaces are isolated" {
    try ensureCache();
    defer cache.deinit();

    var ns_buf: [96]u8 = undefined;
    const namespace = try uniqueLabel("cache-scope", &ns_buf);
    const scoped = cache.scope(namespace);
    const key = "shared-key";

    defer scoped.delete(key) catch {};
    defer cache.delete(key) catch {};

    try scoped.put(key, "scoped-value", .{ .expiration_ttl = 30 });
    try cache.put(key, "default-value", .{ .expiration_ttl = 30 });

    const scoped_value = (try scoped.get(allocator, key)).?;
    defer allocator.free(scoped_value);

    const default_value = (try cache.get(allocator, key)).?;
    defer allocator.free(default_value);

    try std.testing.expectEqualStrings("scoped-value", scoped_value);
    try std.testing.expectEqualStrings("default-value", default_value);
}

test "cache: putAs/as roundtrip typed value" {
    try ensureCache();
    defer cache.deinit();

    var key_buf: [96]u8 = undefined;
    const key = try uniqueLabel("cache-typed", &key_buf);

    defer cache.delete(key) catch {};

    try cache.putAs(key, Profile{
        .id = 42,
        .name = "nurul",
        .active = true,
    }, .{ .expiration_ttl = 30 });

    const profile = (try cache.as(allocator, key, Profile)).?;
    defer freeProfile(profile);

    try std.testing.expectEqual(@as(u32, 42), profile.id);
    try std.testing.expectEqualStrings("nurul", profile.name);
    try std.testing.expect(profile.active);
}

test "cache: as returns invalid type on schema mismatch" {
    try ensureCache();
    defer cache.deinit();

    var key_buf: [96]u8 = undefined;
    const key = try uniqueLabel("cache-typed-mismatch", &key_buf);

    defer cache.delete(key) catch {};

    try cache.putAs(key, Profile{
        .id = 7,
        .name = "mismatch",
        .active = false,
    }, .{ .expiration_ttl = 30 });

    try std.testing.expectError(error.InvalidType, cache.as(allocator, key, ProfileAlias));
}

test "cache: scoped putAs/as roundtrip typed value" {
    try ensureCache();
    defer cache.deinit();

    var ns_buf: [96]u8 = undefined;
    var key_buf: [96]u8 = undefined;

    const namespace = try uniqueLabel("cache-typed-scope", &ns_buf);
    const key = try uniqueLabel("profile", &key_buf);
    const scoped = cache.scope(namespace);

    defer scoped.delete(key) catch {};

    try scoped.putAs(key, Profile{
        .id = 99,
        .name = "scoped-user",
        .active = true,
    }, .{ .expiration_ttl = 30 });

    const profile = (try scoped.as(allocator, key, Profile)).?;
    defer freeProfile(profile);

    try std.testing.expectEqual(@as(u32, 99), profile.id);
    try std.testing.expectEqualStrings("scoped-user", profile.name);
    try std.testing.expect(profile.active);
}

test "cache: expired entries are filtered from get and list" {
    try ensureCache();
    defer cache.deinit();

    var prefix_buf: [96]u8 = undefined;
    const prefix = try uniqueLabel("cache-expired", &prefix_buf);

    var expired_key_buf: [128]u8 = undefined;
    var live_key_buf: [128]u8 = undefined;

    const expired_key = try std.fmt.bufPrint(&expired_key_buf, "{s}-expired", .{prefix});
    const live_key = try std.fmt.bufPrint(&live_key_buf, "{s}-live", .{prefix});

    defer _ = cache.delPrefix(prefix);

    const now: u64 = @intCast(std.time.timestamp());
    try cache.put(expired_key, "stale", .{ .expiration = now });
    try cache.put(live_key, "fresh", .{ .expiration_ttl = 30 });

    try std.testing.expect((try cache.get(allocator, expired_key)) == null);

    const keys = try cache.list(allocator, prefix);
    defer {
        for (keys) |key| allocator.free(key);
        allocator.free(keys);
    }

    try std.testing.expectEqual(@as(usize, 1), keys.len);
    try std.testing.expectEqualStrings(live_key, keys[0]);
}

fn runConcurrentWorker(ctx: *WorkerContext) void {
    const scoped = cache.scope(ctx.ns);

    var key_buf: [96]u8 = undefined;
    var value_buf: [96]u8 = undefined;

    for (0..25) |i| {
        const key = std.fmt.bufPrint(&key_buf, "worker-{d}-key-{d}", .{ ctx.worker_id, i }) catch {
            ctx.err = error.Unexpected;
            return;
        };
        const value = std.fmt.bufPrint(&value_buf, "value-{d}-{d}", .{ ctx.worker_id, i }) catch {
            ctx.err = error.Unexpected;
            return;
        };

        scoped.put(key, value, .{ .expiration_ttl = 60 }) catch |err| {
            ctx.err = err;
            return;
        };

        const found = scoped.get(std.heap.page_allocator, key) catch |err| {
            ctx.err = err;
            return;
        };
        if (found) |bytes| {
            defer std.heap.page_allocator.free(bytes);
            if (!std.mem.eql(u8, bytes, value)) {
                ctx.err = error.Unexpected;
                return;
            }
        } else {
            ctx.err = error.Unexpected;
            return;
        }
    }
}

test "cache: concurrent reads and writes are threadsafe" {
    try ensureCache();
    defer cache.deinit();

    var ns_buf: [96]u8 = undefined;
    const namespace = try uniqueLabel("cache-threadsafe", &ns_buf);
    const scoped = cache.scope(namespace);

    defer {
        _ = scoped.delPrefix("") catch 0;
    }

    var workers = [_]WorkerContext{
        .{ .ns = namespace, .worker_id = 0 },
        .{ .ns = namespace, .worker_id = 1 },
        .{ .ns = namespace, .worker_id = 2 },
        .{ .ns = namespace, .worker_id = 3 },
    };
    var threads: [workers.len]std.Thread = undefined;

    for (&threads, &workers) |*thread, *worker| {
        thread.* = try std.Thread.spawn(.{}, runConcurrentWorker, .{worker});
    }

    for (threads, &workers) |thread, *worker| {
        thread.join();
        if (worker.err) |err| return err;
    }

    const keys = try scoped.list(allocator, "");
    defer {
        for (keys) |key| allocator.free(key);
        allocator.free(keys);
    }

    try std.testing.expectEqual(@as(usize, workers.len * 25), keys.len);
}
