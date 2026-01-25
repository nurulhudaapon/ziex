const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

/// Global cache for components and pages
const cachez = switch (builtin.os.tag) {
    .freestanding, .wasi => struct {
        pub fn Entry(comptime T: type) type {
            return struct {
                key: []const u8,
                value: T,
                expires: u32,

                const Self = @This();

                pub fn init(allocator: Allocator, key: []const u8, value: T, size: u32, expires: u32) Self {
                    _ = allocator;
                    _ = size;
                    return .{
                        .key = key,
                        .value = value,
                        .expires = expires,
                    };
                }

                pub fn expired(self: *Self) bool {
                    return self.ttl() <= 0;
                }

                pub fn ttl(self: *Self) i64 {
                    _ = self;
                    return 0;
                }

                pub fn hit(self: *Self) u8 {
                    _ = self;
                }

                pub fn borrow(self: *Self) void {
                    _ = self;
                }

                pub fn release(self: *Self) void {
                    _ = self;
                }
            };
        }

        pub const Config = struct {
            max_size: u32 = 8000,
            segment_count: u16 = 8,
            gets_per_promote: u8 = 5,
            shrink_ratio: f32 = 0.2,
        };

        pub const PutConfig = struct {
            ttl: u32 = 300,
            size: u32 = 1,
        };

        pub fn Cache(comptime T: type) type {
            return struct {
                allocator: Allocator,

                const Self = @This();

                pub fn init(allocator: Allocator, _: Config) !Self {
                    return .{
                        .allocator = allocator,
                    };
                }

                pub fn deinit(_: *Self) void {}

                pub fn contains(self: *const Self, key: []const u8) bool {
                    _ = key;
                    _ = self;
                    return false;
                }

                pub fn get(self: *Self, key: []const u8) ?*Entry(T) {
                    _ = key;
                    _ = self;
                    return null;
                }

                pub fn getEntry(self: *const Self, key: []const u8) ?*Entry(T) {
                    _ = key;
                    _ = self;
                    return null;
                }

                pub fn put(self: *Self, key: []const u8, value: T, config: PutConfig) !void {
                    _ = key;
                    _ = value;
                    _ = config;
                    _ = self;

                    return;
                }

                pub fn del(self: *Self, key: []const u8) bool {
                    _ = key;
                    _ = self;
                    return false;
                }

                pub fn delPrefix(self: *Self, prefix: []const u8) !usize {
                    _ = prefix;
                    _ = self;
                    return 0;
                }

                pub fn fetch(self: *Self, comptime S: type, key: []const u8, loader: *const fn (state: S, key: []const u8) anyerror!?T, state: S, config: PutConfig) !?*Entry(T) {
                    _ = key;
                    _ = loader;
                    _ = state;
                    _ = config;
                    _ = self;
                    return null;
                }

                pub fn maxSize(self: Self) usize {
                    _ = self;
                    return 0;
                }
            };
        }
    },
    else => @import("cachez"),
};

const CacheEntry = struct {
    html: []const u8,

    pub fn removedFromCache(self: CacheEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.html);
    }
};

var inner: ?cachez.Cache(CacheEntry) = null;
var alloc: ?std.mem.Allocator = null;

/// Initialize the cache (called once at app startup)
pub fn init(allocator: std.mem.Allocator, config: cachez.Config) !void {
    if (inner != null) return;
    alloc = allocator;
    inner = try cachez.Cache(CacheEntry).init(allocator, config);
}

/// Deinitialize the cache
pub fn deinit() void {
    if (inner) |*c| {
        c.deinit();
        inner = null;
    }
}

/// Get cached HTML by key
pub fn get(key: []const u8) ?[]const u8 {
    if (inner) |*c| {
        if (c.get(key)) |entry| {
            defer entry.release();
            return entry.value.html;
        }
    }
    return null;
}

/// Store HTML in cache with TTL
pub fn put(key: []const u8, html: []const u8, ttl_seconds: u32) void {
    if (inner) |*c| {
        const allocator = alloc orelse return;
        const html_copy = allocator.dupe(u8, html) catch return;
        c.put(key, .{ .html = html_copy }, .{ .ttl = ttl_seconds }) catch {
            allocator.free(html_copy);
        };
    }
}

/// Delete cache entry by exact key
pub fn del(key: []const u8) bool {
    if (inner) |*c| return c.del(key);
    return false;
}

/// Delete all cache entries matching a prefix
pub fn delPrefix(prefix: []const u8) usize {
    if (inner) |*c| return c.delPrefix(prefix) catch 0;
    return 0;
}
