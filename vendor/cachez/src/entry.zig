const std = @import("std");
const Allocator = std.mem.Allocator;

const List = @import("list.zig").List;

pub fn Entry(comptime T: type) type {
    const NOTIFY_REMOVAL = comptime std.meta.hasMethod(T, "removedFromCache");

    return struct {
        // the cache key
        key: []const u8,

        // the user supplied value
        value: T,

        // absolute time, in seconds, that the entry expires
        expires: u32,

        // this is, unfortunately needed, since our deinit happens when a call to
        // "release" makes _rc == 0. This can be triggered from application code,
        // which doesn't know anything about our allocator.
        _allocator: Allocator,

        // the node in the linked list
        _node: *List(*Self).Node,

        // size of the object as specified when put/fetch is called
        // necessary so that when the entry is removed from the cache
        // we can subtract this size from the cache size
        _size: u32,

        // atomically increment each time this entry is retrieved
        // entries are only promoted to the head of the recency list on every
        // $config.gets_per_promote gets.
        _gets: u8,

        // incremented whenever the value is lent to the application, decremented
        // whenever the application releases the entry back.
        // important to avoid calling removedFromCache while the entry is being leant
        // (rc == reference_count)
        _rc: u16,

        const Self = @This();

        pub fn init(allocator: Allocator, key: []const u8, value: T, size: u32, expires: u32) Self {
            return .{
                ._rc = 1, // the cache itself has an rc
                ._gets = 0,
                ._size = size,
                ._node = undefined,
                ._allocator = allocator,
                .key = key,
                .value = value,
                .expires = expires,
            };
        }

        pub fn expired(self: *Self, io: std.Io) bool {
            return self.ttl(io) <= 0;
        }

        pub fn ttl(self: *Self, io: std.Io) i64 {
            return self.expires - std.Io.Timestamp.now(io, .real).toSeconds();
        }

        pub fn hit(self: *Self) u8 {
            // wrapping is fine.
            const prev = @atomicRmw(u8, &self._gets, .Add, 1, .monotonic);
            const result, _ = @addWithOverflow(prev, 1);
            return result;
        }

        pub fn borrow(self: *Self) void {
            _ = @atomicRmw(u16, &self._rc, .Add, 1, .monotonic);
        }

        pub fn release(self: *Self) void {
            if (@atomicRmw(u16, &self._rc, .Sub, 1, .monotonic) != 1) {
                return;
            }

            const allocator = self._allocator;

            const node = self._node;
            std.debug.assert(node.prev == null);
            std.debug.assert(node.next == null);

            if (NOTIFY_REMOVAL) {
                self.value.removedFromCache(allocator);
            }
            allocator.free(self.key);
            allocator.destroy(node);
            allocator.destroy(self);
        }
    };
}
