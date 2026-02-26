const std = @import("std");

pub const Entry = @import("entry.zig").Entry;
const Segment = @import("segment.zig").Segment;

const Allocator = std.mem.Allocator;

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
        segment_mask: u16,
        segments: []Segment(T),

        const Self = @This();

        pub fn init(allocator: Allocator, config: Config) !Self {
            const segment_count = config.segment_count;
            if (segment_count == 0) return error.SegmentBucketNotPower2;
            // has to be a power of 2
            if ((segment_count & (segment_count - 1)) != 0) return error.SegmentBucketNotPower2;

            const shrink_ratio = config.shrink_ratio;
            if (shrink_ratio == 0 or shrink_ratio > 1) return error.SpaceToFreeInvalid;

            const segment_max_size = config.max_size / segment_count;
            const segment_config = .{
                .max_size = segment_max_size,
                .target_size = segment_max_size - @as(u32, @intFromFloat(@as(f32, @floatFromInt(segment_max_size)) * shrink_ratio)),
                .gets_per_promote = config.gets_per_promote,
            };

            const segments = try allocator.alloc(Segment(T), segment_count);
            for (0..segment_count) |i| {
                segments[i] = Segment(T).init(allocator, segment_config);
            }

            return .{
                .allocator = allocator,
                .segments = segments,
                .segment_mask = segment_count - 1,
            };
        }

        pub fn deinit(self: *Self) void {
            const allocator = self.allocator;
            for (self.segments) |*segment| {
                segment.deinit();
            }
            allocator.free(self.segments);
        }

        pub fn contains(self: *const Self, key: []const u8) bool {
            return self.getSegment(key).contains(key);
        }

        pub fn get(self: *Self, key: []const u8) ?*Entry(T) {
            return self.getSegment(key).get(key);
        }

        pub fn getEntry(self: *const Self, key: []const u8) ?*Entry(T) {
            return self.getSegment(key).getEntry(key);
        }

        pub fn put(self: *Self, key: []const u8, value: T, config: PutConfig) !void {
            _ = try self.getSegment(key).put(self.allocator, key, value, config);
        }

        pub fn del(self: *Self, key: []const u8) bool {
            return self.getSegment(key).del(key);
        }

        pub fn delPrefix(self: *Self, prefix: []const u8) !usize {
            var total: usize = 0;
            const allocator = self.allocator;
            for (self.segments) |*segment| {
                total += try segment.delPrefix(allocator, prefix);
            }
            return total;
        }

        pub fn fetch(self: *Self, comptime S: type, key: []const u8, loader: *const fn (state: S, key: []const u8) anyerror!?T, state: S, config: PutConfig) !?*Entry(T) {
            return self.getSegment(key).fetch(S, self.allocator, key, loader, state, config);
        }

        pub fn maxSize(self: Self) usize {
            return self.segments[0].max_size * self.segments.len;
        }

        fn getSegment(self: *const Self, key: []const u8) *Segment(T) {
            const hash_code = std.hash.Wyhash.hash(0, key);
            return &self.segments[@intCast(hash_code & self.segment_mask)];
        }
    };
}

test {
    std.testing.refAllDecls(@This());
}

const t = @import("t.zig");
test "cache: invalid config" {
    try t.expectError(error.SegmentBucketNotPower2, Cache(u8).init(t.allocator, .{ .segment_count = 0 }));
    try t.expectError(error.SegmentBucketNotPower2, Cache(u8).init(t.allocator, .{ .segment_count = 3 }));
    try t.expectError(error.SegmentBucketNotPower2, Cache(u8).init(t.allocator, .{ .segment_count = 10 }));
    try t.expectError(error.SegmentBucketNotPower2, Cache(u8).init(t.allocator, .{ .segment_count = 30 }));
}

test "cache: get null" {
    var cache = t.initCache();
    defer cache.deinit();
    try t.expectEqual(@as(?*t.Entry, null), cache.get("nope"));
}

test "cache: get / set / del" {
    var cache = t.initCache();
    defer cache.deinit();
    try t.expectEqual(false, cache.contains("k1"));

    try cache.put("k1", 1, .{});
    const e1 = cache.get("k1").?;
    try t.expectEqual(false, e1.expired());
    try t.expectEqual(@as(i32, 1), e1.value);
    try t.expectEqual(true, cache.contains("k1"));
    e1.release();

    try cache.put("k2", 2, .{});
    const e2 = cache.get("k2").?;
    try t.expectEqual(false, e2.expired());
    try t.expectEqual(@as(i32, 2), e2.value);
    try t.expectEqual(true, cache.contains("k2"));
    e2.release();

    try cache.put("k1", 1, .{});
    var e1a = cache.get("k1").?;
    try t.expectEqual(false, e1a.expired());
    try t.expectEqual(@as(i32, 1), e1a.value);
    try t.expectEqual(true, cache.contains("k2"));
    e1a.release();

    try t.expectEqual(true, cache.del("k1"));
    try t.expectEqual(false, cache.contains("k1"));
    try t.expectEqual(true, cache.contains("k2"));

    // delete on non-key is no-op
    try t.expectEqual(false, cache.del("k1"));
    try t.expectEqual(false, cache.contains("k1"));
    try t.expectEqual(true, cache.contains("k2"));

    try t.expectEqual(true, cache.del("k2"));
    try t.expectEqual(false, cache.contains("k1"));
    try t.expectEqual(false, cache.contains("k2"));
}

test "cache: get expired" {
    var cache = t.initCache();
    defer cache.deinit();

    try cache.put("k1", 1, .{ .ttl = 0 });
    const e1a = cache.getEntry("k1").?;
    defer e1a.release();
    try t.expectEqual(true, e1a.expired());
    try t.expectEqual(@as(i32, 1), e1a.value);

    // getEntry on expired won't remove it, it's like a peek
    const e1b = cache.getEntry("k1").?;
    defer e1b.release();
    try t.expectEqual(true, e1b.expired());
    try t.expectEqual(@as(i32, 1), e1b.value);

    // contains on expired won't remove it either
    try t.expectEqual(true, cache.contains("k1"));
    try t.expectEqual(true, cache.contains("k1"));

    // but a get on an expired does remove it
    try t.expectEqual(@as(?*t.Entry, null), cache.get("k1"));
    try t.expectEqual(false, cache.contains("k1"));
}

test "cache: ttl" {
    var cache = t.initCache();
    defer cache.deinit();

    // default ttl
    try cache.put("k1", 1, .{});
    const e1 = cache.get("k1").?;
    defer e1.release();
    const ttl1 = e1.ttl();
    try t.expectEqual(true, ttl1 >= 299 and ttl1 <= 300);

    // explicit ttl
    try cache.put("k2", 1, .{ .ttl = 60 });
    const e2 = cache.get("k2").?;
    defer e2.release();
    const ttl2 = e2.ttl();
    try t.expectEqual(true, ttl2 >= 59 and ttl2 <= 60);
}

test "cache: get promotion" {
    var cache = try Cache(i32).init(t.allocator, .{ .segment_count = 1, .gets_per_promote = 3 });
    defer cache.deinit();

    try cache.put("k1", 1, .{});
    try cache.put("k2", 2, .{});
    try cache.put("k3", 3, .{});
    try testSingleSegmentCache(&cache, &[_][]const u8{ "k3", "k2", "k1" }, &.{ 3, 2, 1 }, false);

    // must get $gets_per_promote before it promotes, none of these reach that
    cache.get("k1").?.release();
    cache.get("k1").?.release();
    cache.get("k2").?.release();
    cache.get("k2").?.release();
    cache.get("k3").?.release();
    try testSingleSegmentCache(&cache, &[_][]const u8{ "k3", "k2", "k1" }, &.{ 3, 2, 1 }, false);

    // should be promoted now
    cache.get("k1").?.release();
    try testSingleSegmentCache(&cache, &[_][]const u8{ "k1", "k3", "k2" }, &.{ 1, 3, 2 }, false);

    // should be promoted now
    cache.get("k2").?.release();
    try testSingleSegmentCache(&cache, &[_][]const u8{ "k2", "k1", "k3" }, &.{ 2, 1, 3 }, false);
}

test "cache: get promotion expired" {
    var cache = try Cache(i32).init(t.allocator, .{ .segment_count = 1, .gets_per_promote = 3 });
    defer cache.deinit();

    try cache.put("k1", 1, .{ .ttl = 0 });
    try cache.put("k2", 2, .{});
    try testSingleSegmentCache(&cache, &[_][]const u8{ "k2", "k1" }, &.{ 2, 1 }, true);

    // expired items never get promoted
    cache.getEntry("k1").?.release();
    cache.getEntry("k1").?.release();
    cache.getEntry("k1").?.release();
    cache.getEntry("k1").?.release();
    try testSingleSegmentCache(&cache, &[_][]const u8{ "k2", "k1" }, &.{ 2, 1 }, true);
}

test "cache: fetch" {
    var cache = t.initCache();
    defer cache.deinit();

    var fetch_state = FetchState{ .called = 0 };
    const e1a = (try cache.fetch(*FetchState, "k1", doFetch, &fetch_state, .{})).?;
    defer e1a.release();
    try t.expectString("k1", e1a.key);
    try t.expectEqual(@as(i32, 1), fetch_state.called);

    // same key, fetch_state.called doesn't increment because doFetch isn't called!
    const e1b = (try cache.fetch(*FetchState, "k1", doFetch, &fetch_state, .{})).?;
    defer e1b.release();
    try t.expectString("k1", e1b.key);
    try t.expectEqual(@as(i32, 1), fetch_state.called);

    // different key
    const e2 = (try cache.fetch(*FetchState, "k2", doFetch, &fetch_state, .{})).?;
    defer e2.release();
    try t.expectString("k2", e2.key);
    try t.expectEqual(@as(i32, 2), fetch_state.called);

    // this key makes doFetch return null
    try t.expectEqual(@as(?*t.Entry, null), try cache.fetch(*FetchState, "return null", doFetch, &fetch_state, .{}));
    try t.expectEqual(@as(i32, 3), fetch_state.called);

    // we don't cache null, so this will hit doFetch again
    try t.expectEqual(@as(?*t.Entry, null), try cache.fetch(*FetchState, "return null", doFetch, &fetch_state, .{}));
    try t.expectEqual(@as(i32, 4), fetch_state.called);

    // this will return an error
    try t.expectError(error.FetchFail, cache.fetch(*FetchState, "return error", doFetch, &fetch_state, .{}));
    try t.expectEqual(@as(i32, 5), fetch_state.called);
}

test "cache: enforce max_size" {
    var cache = try Cache(i32).init(t.allocator, .{ .max_size = 5, .segment_count = 1 });
    defer cache.deinit();

    try cache.put("k1", 1, .{});
    try cache.put("k2", 2, .{});
    try cache.put("k3", 3, .{});
    try cache.put("k4", 4, .{});
    try cache.put("k5", 5, .{});
    try testSingleSegmentCache(&cache, &[_][]const u8{ "k5", "k4", "k3", "k2", "k1" }, &.{ 5, 4, 3, 2, 1 }, false);

    try cache.put("k6", 6, .{});
    try testSingleSegmentCache(&cache, &[_][]const u8{ "k6", "k5", "k4", "k3" }, &.{ 6, 5, 4, 3 }, false);

    try cache.put("k7", 7, .{});
    try testSingleSegmentCache(&cache, &[_][]const u8{ "k7", "k6", "k5", "k4", "k3" }, &.{ 7, 6, 5, 4, 3 }, false);

    try cache.put("k6", 6, .{});
    try testSingleSegmentCache(&cache, &[_][]const u8{ "k6", "k7", "k5", "k4", "k3" }, &.{ 6, 7, 5, 4, 3 }, false);

    try cache.put("k8", 8, .{ .size = 3 });
    try testSingleSegmentCache(&cache, &[_][]const u8{ "k8", "k6" }, &.{ 8, 6 }, false);
}

test "cache: enforce sized() " {
    var cache = try Cache(TestSized).init(t.allocator, .{ .max_size = 12, .segment_count = 1 });
    defer cache.deinit();

    try cache.put("k1", .{ .id = 1, .s = 1 }, .{});
    try cache.put("k2", .{ .id = 2, .s = 2 }, .{});
    try cache.put("k3", .{ .id = 3, .s = 3 }, .{});
    try t.expectEqual(true, cache.contains("k1"));
    try t.expectEqual(true, cache.contains("k2"));
    try t.expectEqual(true, cache.contains("k3"));

    try cache.put("k4", .{ .id = 4, .s = 7 }, .{});
    try t.expectEqual(false, cache.contains("k1"));
    try t.expectEqual(false, cache.contains("k2"));
    try t.expectEqual(true, cache.contains("k3"));
    try t.expectEqual(true, cache.contains("k4"));
}

test "cache: get max_size" {
    var cache = try Cache(i32).init(t.allocator, .{ .max_size = 1100, .segment_count = 8 });
    defer cache.deinit();

    try t.expectEqual(@as(usize, 1096), cache.maxSize());
}

test "cache: delPrefix" {
    var cache = try Cache(i32).init(t.allocator, .{ .max_size = 100 });
    defer cache.deinit();

    try cache.put("a1", 1, .{});
    try cache.put("bb2", 2, .{});
    try cache.put("bc3", 3, .{});
    try cache.put("a4", 4, .{});
    try cache.put("a5", 5, .{});

    try t.expectEqual(@as(usize, 0), try cache.delPrefix("z"));
    try t.expectEqual(true, cache.contains("bb2"));
    try t.expectEqual(true, cache.contains("bc3"));
    try t.expectEqual(true, cache.contains("a1"));
    try t.expectEqual(true, cache.contains("a4"));
    try t.expectEqual(true, cache.contains("a5"));

    try t.expectEqual(@as(usize, 3), try cache.delPrefix("a"));
    try t.expectEqual(true, cache.contains("bb2"));
    try t.expectEqual(true, cache.contains("bc3"));
    try t.expectEqual(false, cache.contains("a1"));
    try t.expectEqual(false, cache.contains("a4"));
    try t.expectEqual(false, cache.contains("a5"));

    try t.expectEqual(@as(usize, 1), try cache.delPrefix("bb"));
    try t.expectEqual(false, cache.contains("bb2"));
    try t.expectEqual(true, cache.contains("bc3"));
    try t.expectEqual(false, cache.contains("a1"));
    try t.expectEqual(false, cache.contains("a4"));
    try t.expectEqual(false, cache.contains("a5"));
}

// if NotifiedValue.deinit isn't called, we expect a memory leak to be detected
test "cache: entry has deinit" {
    var cache = try Cache(NotifiedValue).init(t.allocator, .{ .segment_count = 1, .max_size = 2 });
    defer cache.deinit();

    try cache.put("k1", NotifiedValue.init("abc"), .{});

    // overwriting should free the old
    try cache.put("k1", NotifiedValue.init("new"), .{});

    // delete should free
    _ = cache.del("k1");

    // max_size enforcerr should free
    try cache.put("k1", NotifiedValue.init("abc"), .{});
    try cache.put("k2", NotifiedValue.init("abc"), .{});
    try cache.put("k3", NotifiedValue.init("abc"), .{});
    try t.expectEqual(false, cache.contains("k1")); // make sure max_size enforcer really did run
}

// contains_only == true is necesary for some tests because calling cache.get can
// modify the cache (e.g. if an item is expired)
fn testSingleSegmentCache(cache: *Cache(i32), expected_keys: []const []const u8, expected_values: []const i32, contains_only: bool) !void {
    for (expected_keys, expected_values) |k, v| {
        if (contains_only) {
            try t.expectEqual(true, cache.contains(k));
        } else {
            const entry = cache.get(k).?;
            try t.expectEqual(v, entry.value);
            entry.release();
        }
    }
    // only works for caches with 1 segment, else we don't know how the keys
    // are distributed (I mean, we know the hashing algorithm, so we could
    // figure it out, but we're testing this assuming that if 1 segment works
    // N segment works. This seems reasonable since there's no real link between
    // segments)
    try testList(cache.segments[0].list, expected_values);
}

const NotifiedValue = struct {
    data: []const u8,

    fn init(data: []const u8) NotifiedValue {
        return .{ .data = t.allocator.dupe(u8, data) catch unreachable };
    }

    pub fn removedFromCache(self: NotifiedValue, allocator: Allocator) void {
        allocator.free(self.data);
    }
};

const FetchState = struct {
    called: i32,
};

fn doFetch(state: *FetchState, key: []const u8) !?i32 {
    state.called += 1;
    if (std.mem.eql(u8, key, "return null")) {
        return null;
    }
    if (state.called == 5) {
        return error.FetchFail;
    }
    return state.called;
}

const List = @import("list.zig").List;
fn testList(list: List(*Entry(i32)), expected: []const i32) !void {
    var node = list.head;
    for (expected) |e| {
        try t.expectEqual(e, node.?.value.value);
        node = node.?.next;
    }
    try t.expectEqual(true, node == null);

    node = list.tail;
    var i: usize = expected.len;
    while (i > 0) : (i -= 1) {
        try t.expectEqual(expected[i - 1], node.?.value.value);
        node = node.?.prev;
    }
    try t.expectEqual(true, node == null);
}

const TestSized = struct {
    id: u32,
    s: u32,

    pub fn size(self: TestSized) u32 {
        return self.s;
    }
};
