const Cache = @This();

const std = @import("std");
const builtin = @import("builtin");

const zx = @import("../../root.zig");
const Kv = @import("Kv.zig");

const Allocator = std.mem.Allocator;

pub const cachez = @import("Cache/Mem/cache.zig");

const entry_version: u8 = 1;
const header_len = 9;

backend: Kv = Kv.failing,
namespace: []const u8 = "default",
allocator: std.mem.Allocator,
io: std.Io,
memory: ?*cachez.Cache(CacheEntry) = null,

pub const PutOptions = Kv.PutOptions;

pub const Config = struct {
    max_size: u32 = 8000,
    segment_count: u16 = 8,
    gets_per_promote: u8 = 5,
    shrink_ratio: f32 = 0.2,
};

const CacheEntry = struct {
    bytes: []u8,

    pub fn removedFromCache(self: CacheEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.bytes);
    }
};

const StoredEntry = struct {
    expires_at: ?u64,
    payload: []const u8,
};

pub fn init(io: std.Io, allocator: Allocator, kv: Kv, config: Config) !Cache {
    const cachez_config = cachez.Config{
        .max_size = config.max_size,
        .segment_count = config.segment_count,
        .gets_per_promote = config.gets_per_promote,
        .shrink_ratio = config.shrink_ratio,
    };

    const memory = try allocator.create(cachez.Cache(CacheEntry));
    errdefer allocator.destroy(memory);
    memory.* = try cachez.Cache(CacheEntry).init(io, allocator, cachez_config);

    return .{
        .backend = kv,
        .namespace = "default",
        .allocator = allocator,
        .io = io,
        .memory = memory,
    };
}

pub fn deinit(self: *Cache) void {
    if (self.memory) |mem| {
        const allocator = mem.allocator;
        mem.deinit();
        allocator.destroy(mem);
        self.memory = null;
    }
}

pub fn scoped(self: Cache, comptime ns: @EnumLiteral()) Cache {
    return .{
        .backend = self.backend,
        .namespace = @tagName(ns),
        .allocator = self.allocator,
        .io = self.io,
        .memory = self.memory,
    };
}

fn boundBackend(self: Cache) Kv {
    return .{
        .vtable = self.backend.vtable,
        .userdata = self.backend.userdata,
        .namespace = if (self.namespace.len == 0) "default" else self.namespace,
    };
}

pub fn get(self: Cache, allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
    const io = self.io;
    const memory = self.memory orelse return error.CacheUnavailable;

    const scoped_key = try scopedKey(allocator, self.namespace, key);
    defer allocator.free(scoped_key);

    if (memory.get(scoped_key)) |entry| {
        defer entry.release();
        return @as(?[]u8, try allocator.dupe(u8, entry.value.bytes));
    }

    const backend = self.boundBackend();
    const encoded = (try backend.get(allocator, key)) orelse return null;
    defer allocator.free(encoded);

    const decoded = try decodeStoredEntry(encoded);
    if (isExpired(io, decoded.expires_at)) {
        try backend.delete(key);
        _ = memory.del(scoped_key);
        return null;
    }

    try putMemoryEntryLocked(self, scoped_key, decoded.payload, ttlFromExpiration(io, decoded.expires_at));
    return @as(?[]u8, try allocator.dupe(u8, decoded.payload));
}

pub fn as(self: Cache, allocator: std.mem.Allocator, key: []const u8, comptime T: type) !?T {
    const raw = (try self.get(allocator, key)) orelse return null;
    defer allocator.free(raw);

    const expected_hash = zx.util.zxon.schema(T).hash;
    if (try storedTypeHash(raw) != expected_hash) return error.InvalidType;

    const TypedValue = struct {
        hash: u64,
        value: T,
    };

    const parsed = try zx.util.zxon.parse(TypedValue, allocator, raw, .{});
    return parsed.value;
}

pub fn put(self: Cache, key: []const u8, value: []const u8, opts: PutOptions) !void {
    _ = self.memory orelse return error.CacheUnavailable;

    const io = self.io;
    const allocator = self.allocator;
    const encoded = try encodeStoredEntry(io, allocator, value, opts);
    defer allocator.free(encoded);

    try self.boundBackend().put(key, encoded, .{});

    const scoped_key = try scopedKey(allocator, self.namespace, key);
    defer allocator.free(scoped_key);
    try putMemoryEntryLocked(self, scoped_key, value, ttlFromOptions(io, opts));
}

pub fn putAs(self: Cache, key: []const u8, value: anytype, opts: PutOptions) !void {
    _ = self.memory orelse return error.CacheUnavailable;

    const ValueType = @TypeOf(value);
    const TypedValue = struct {
        hash: u64,
        value: ValueType,
    };

    const allocator = self.allocator;
    var writer = std.Io.Writer.Allocating.init(allocator);
    defer writer.deinit();

    try zx.util.zxon.serialize(TypedValue{
        .hash = zx.util.zxon.schema(ValueType).hash,
        .value = value,
    }, &writer.writer, .{});

    try self.put(key, writer.written(), opts);
}

pub fn delete(self: Cache, key: []const u8) !void {
    const memory = self.memory orelse return error.CacheUnavailable;
    const allocator = self.allocator;
    const scoped_key = try scopedKey(allocator, self.namespace, key);
    defer allocator.free(scoped_key);

    _ = memory.del(scoped_key);
    try self.boundBackend().delete(key);
}

pub fn list(self: Cache, allocator: std.mem.Allocator, prefix: []const u8) ![][]u8 {
    const io = self.io;
    const memory = self.memory orelse return error.CacheUnavailable;
    const backend = self.boundBackend();
    const keys = try backend.list(allocator, prefix);
    defer {
        for (keys) |key| allocator.free(key);
        allocator.free(keys);
    }

    var live_keys: std.ArrayList([]u8) = .empty;
    defer live_keys.deinit(allocator);

    for (keys) |key| {
        const encoded = (try backend.get(allocator, key)) orelse continue;
        defer allocator.free(encoded);

        const decoded = try decodeStoredEntry(encoded);
        if (isExpired(io, decoded.expires_at)) {
            try backend.delete(key);

            const scoped_key = try scopedKey(allocator, self.namespace, key);
            defer allocator.free(scoped_key);
            _ = memory.del(scoped_key);
            continue;
        }

        try live_keys.append(allocator, try allocator.dupe(u8, key));
    }

    return live_keys.toOwnedSlice(allocator);
}

pub fn del(self: Cache, key: []const u8) bool {
    const memory = self.memory orelse return false;
    const allocator = self.allocator;
    const backend = self.boundBackend();
    const existing = backend.get(allocator, key) catch null;
    const existed = if (existing) |bytes| blk: {
        allocator.free(bytes);
        break :blk true;
    } else false;

    const scoped_key = scopedKey(allocator, self.namespace, key) catch return existed;
    defer allocator.free(scoped_key);

    const memory_deleted = memory.del(scoped_key);
    backend.delete(key) catch {};
    return existed or memory_deleted;
}

pub fn delPrefix(self: Cache, prefix: []const u8) !usize {
    const memory = self.memory orelse return error.CacheUnavailable;
    const allocator = self.allocator;
    const backend = self.boundBackend();
    const keys = try backend.list(allocator, prefix);
    defer {
        for (keys) |key| allocator.free(key);
        allocator.free(keys);
    }

    var deleted: usize = 0;
    for (keys) |key| {
        try backend.delete(key);

        const scoped_key = try scopedKey(allocator, self.namespace, key);
        defer allocator.free(scoped_key);
        _ = memory.del(scoped_key);
        deleted += 1;
    }

    return deleted;
}

fn scopedKey(allocator: Allocator, ns: []const u8, key: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}\x1f{s}", .{ ns, key });
}

fn encodeStoredEntry(io: std.Io, allocator: Allocator, payload: []const u8, opts: PutOptions) ![]u8 {
    const expires_at = try expirationFromOptions(io, opts);
    const encoded = try allocator.alloc(u8, header_len + payload.len);
    encoded[0] = entry_version;
    std.mem.writeInt(u64, encoded[1..header_len], expires_at orelse 0, .little);
    @memcpy(encoded[header_len..], payload);
    return encoded;
}

fn decodeStoredEntry(encoded: []const u8) !StoredEntry {
    if (encoded.len < header_len or encoded[0] != entry_version) return error.InvalidCacheEntry;

    const expires_raw = std.mem.readInt(u64, encoded[1..header_len], .little);
    return .{
        .expires_at = if (expires_raw == 0) null else expires_raw,
        .payload = encoded[header_len..],
    };
}

fn now(io: std.Io) u64 {
    if (comptime builtin.os.tag == .freestanding or builtin.os.tag == .wasi) return 0;
    const ts = std.Io.Timestamp.now(io, .real);
    return @as(u64, @intCast(@divTrunc(ts.nanoseconds, 1_000_000_000)));
}

fn expirationFromOptions(io: std.Io, opts: PutOptions) !?u64 {
    const ttl = opts.ttl orelse return null;
    const secs = ttl.toSeconds();
    if (secs <= 0) return now(io);
    return now(io) + @as(u64, @intCast(secs));
}

fn ttlFromOptions(_: std.Io, opts: PutOptions) ?u32 {
    const ttl = opts.ttl orelse return null;
    const secs = ttl.toSeconds();
    if (secs <= 0) return 0;
    return clampTtl(@as(u64, @intCast(secs)));
}

fn ttlFromExpiration(io: std.Io, expires_at: ?u64) ?u32 {
    const expiration = expires_at orelse return null;
    const current_now = now(io);
    if (expiration <= current_now) return 0;
    return clampTtl(expiration - current_now);
}

fn clampTtl(ttl: u64) u32 {
    return std.math.cast(u32, ttl) orelse std.math.maxInt(u32);
}

fn isExpired(io: std.Io, expires_at: ?u64) bool {
    const expiration = expires_at orelse return false;
    return expiration <= now(io);
}

fn putMemoryEntryLocked(self: Cache, scoped_key: []const u8, value: []const u8, ttl_seconds: ?u32) !void {
    const io = self.io;
    const memory = self.memory orelse return error.CacheUnavailable;
    const value_copy = try memory.allocator.dupe(u8, value);
    errdefer memory.allocator.free(value_copy);

    try memory.put(scoped_key, .{ .bytes = value_copy }, .{
        .ttl = cachezSafeTtl(io, ttl_seconds),
    });
}

fn cachezSafeTtl(io: std.Io, ttl_seconds: ?u32) u32 {
    const current_now = now(io);
    const max_u32 = std.math.maxInt(u32);
    if (current_now >= max_u32) return 0;

    const max_ttl = max_u32 - @as(u32, @intCast(current_now));
    return @min(ttl_seconds orelse max_ttl, max_ttl);
}

fn storedTypeHash(raw: []const u8) !u64 {
    var i: usize = 0;

    while (i < raw.len and std.ascii.isWhitespace(raw[i])) : (i += 1) {}
    if (i >= raw.len or raw[i] != '[') return error.InvalidType;
    i += 1;

    while (i < raw.len and std.ascii.isWhitespace(raw[i])) : (i += 1) {}
    const start = i;

    while (i < raw.len and std.ascii.isDigit(raw[i])) : (i += 1) {}
    if (start == i) return error.InvalidType;

    return std.fmt.parseUnsigned(u64, raw[start..i], 10);
}

pub const failing: Cache = .{
    .allocator = .failing,
    .io = .failing,
    .backend = .failing,
};
