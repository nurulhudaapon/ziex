const std = @import("std");
const cache = @import("cache.zig");

const Io = std.Io;
const Allocator = std.mem.Allocator;

pub fn Segment(comptime T: type) type {
    const Entry = cache.Entry(T);
    const List = @import("list.zig").List(*Entry);
    const IS_SIZED = comptime std.meta.hasFn(T, "size");

    return struct {
        io: Io,

        // the current size.
        size: u32,

        // the maximum size we should allow this segment to grow to
        max_size: u32,

        // the size we should roughly trim to when we've reached max_size
        target_size: u32,

        // items only get promoted on every N gets.
        gets_per_promote: u8,

        // a double linked list with most recently used items at the head
        // has its own internal mutex for thread-safety.
        list: List,

        // mutex for lookup and size
        mutex: Io.RwLock,

        // key => entry
        lookup: std.StringHashMap(*Entry),

        const Self = @This();

        pub fn init(io: Io, allocator: Allocator, config: anytype) Self {
            return .{
                .io = io,
                .size = 0,
                .mutex = .init,
                .max_size = config.max_size,
                .target_size = config.target_size,
                .gets_per_promote = config.gets_per_promote,
                .list = List.init(),
                .lookup = std.StringHashMap(*Entry).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            const io = self.io;
            var list = &self.list;
            var it = self.lookup.iterator();
            while (it.next()) |kv| {
                const entry = kv.value_ptr.*;
                list.remove(io, entry._node);
                entry.release();
            }
            self.lookup.deinit();
        }

        pub fn contains(self: *Self, key: []const u8) bool {
            const io = self.io;
            self.mutex.lockSharedUncancelable(io);
            defer self.mutex.unlockShared(io);
            return self.lookup.contains(key);
        }

        pub fn get(self: *Self, key: []const u8) ?*Entry {
            const io = self.io;
            const entry = self.getInternal(key) orelse return null;

            if (entry.expired(io)) {
                // release getInternal's borrow
                entry.release();

                self.mutex.lockUncancelable(io);
                _ = self.lookup.remove(key);
                self.size -= entry._size;
                self.mutex.unlock(io);
                self.list.remove(io, entry._node);

                // and now release the cache's implicit borrow
                entry.release();
                return null;
            }

            if (@rem(entry.hit(), self.gets_per_promote) == 0) {
                self.list.moveToFront(io, entry._node);
            }

            return entry;
        }

        pub fn getEntry(self: *Self, key: []const u8) ?*Entry {
            const entry = self.getInternal(key) orelse return null;

            const io = self.io;
            if (!entry.expired(io) and @rem(entry.hit(), self.gets_per_promote) == 0) {
                self.list.moveToFront(io, entry._node);
            }

            return entry;
        }

        // Used by both get and getEntry. Those two methods differ in their handling
        // of expiration, but they share the following to fetch the entry.
        fn getInternal(self: *Self, key: []const u8) ?*Entry {
            const io = self.io;
            self.mutex.lockSharedUncancelable(io);
            const optional_entry = self.lookup.get(key);
            const entry = optional_entry orelse {
                self.mutex.unlockShared(io);
                return null;
            };

            // Even though entry.borrow() increments entry._gc atomically, it has to
            // be called under the mutex. If we move the call to entry.borrow() after
            // releating the mutex, a del or put could slip in, see that _gc == 0
            // and call removedFromCache.
            // (And, we want _gc incremented atomically, because this is a shared
            // read lock and multiple threads could be accessing the entry concurrently)
            entry.borrow();
            self.mutex.unlockShared(io);

            return entry;
        }

        pub fn put(self: *Self, allocator: Allocator, key: []const u8, value: T, config: cache.PutConfig) !*Entry {
            const io = self.io;
            const entry_size = if (IS_SIZED) T.size(value) else config.size;
            const expires = @as(u32, @intCast(std.Io.Timestamp.now(io, .real).toSeconds())) + config.ttl;

            var lookup = &self.lookup;
            var existing_entry: ?*Entry = null;
            const entry = try allocator.create(Entry);

            var segment_size = blk: {
                // This blocks exist so that we can correctly errdefer. This it a common
                // issue with errdefer: there can be a point before the function returns
                // where you no longer want to rollback.
                errdefer allocator.destroy(entry);

                const node = try allocator.create(List.Node);
                errdefer allocator.destroy(node);

                // Tempting to only dupe this if this is a new entry for this key. But
                // that adds a lot of complexity and might not even work. First, it would
                // require dupe under lock (in the gop.found_existing == false case).
                // Second, there are features that rely on entry.key. Now, duping under
                // lock is probably worth it in exchange for less duping. And we could
                // point entry.key = gop.key_ptr.*, but I'm not sure that would work
                // in all cases. Like, who/when do we free the key? If we free it
                // when the item is removed from the cache, then you'd have some still
                // referenced entries with an undefined key. Because those entries would
                // no longer be in the cache, maybe that's fine, but it's risky and
                // could easily be messed up in future code.
                const owned_key = try allocator.dupe(u8, key);
                errdefer allocator.free(owned_key);

                node.* = List.Node{ .value = entry };
                entry.* = Entry.init(allocator, owned_key, value, entry_size, expires);
                entry._node = node;

                {
                    self.mutex.lockUncancelable(io);
                    defer self.mutex.unlock(io);

                    var size = self.size;
                    const gop = try lookup.getOrPut(owned_key);

                    if (gop.found_existing) {
                        existing_entry = gop.value_ptr.*;
                        gop.value_ptr.* = entry;
                        gop.key_ptr.* = owned_key;
                        size = size - existing_entry.?._size + entry_size;
                    } else {
                        gop.value_ptr.* = entry;
                        size = size + entry_size;
                    }
                    self.size = size;
                    break :blk size;
                }
            };

            var list = &self.list;
            if (existing_entry) |existing| {
                list.remove(io, existing._node);
                existing.release();
            }
            list.insert(io, entry._node);

            if (segment_size <= self.max_size) {
                // we're still under our max_size
                return entry;
            }

            // we need to free some space, we're going to free until our segment size
            // is under our target_size
            const target_size = self.target_size;

            self.mutex.lockUncancelable(io);
            defer self.mutex.unlock(io);
            // recheck
            segment_size = self.size;
            while (segment_size > target_size) {
                const removed_node = list.removeTail() orelse break;
                const removed_entry = removed_node.value;

                const existed_in_lookup = lookup.remove(removed_entry.key);
                std.debug.assert(existed_in_lookup == true);

                segment_size -= removed_entry._size;
                removed_entry.release();
            }
            // we're still under lock
            self.size = segment_size;

            return entry;
        }

        // TOOD: singleflight
        pub fn fetch(self: *Self, comptime S: type, allocator: Allocator, key: []const u8, loader: *const fn (state: S, key: []const u8) anyerror!?T, state: S, config: cache.PutConfig) !?*Entry {
            if (self.get(key)) |v| {
                return v;
            }
            if (try loader(state, key)) |value| {
                const entry = try self.put(allocator, key, value, config);
                entry.borrow();
                return entry;
            }
            return null;
        }

        pub fn del(self: *Self, key: []const u8) bool {
            const io = self.io;
            self.mutex.lockUncancelable(io);
            const existing = self.lookup.fetchRemove(key);
            const map_entry = existing orelse {
                self.mutex.unlock(io);
                return false;
            };
            const entry = map_entry.value;
            self.size -= entry._size;
            self.mutex.unlock(io);

            self.list.remove(io, entry._node);
            entry.release();
            return true;
        }

        // This is an expensive call (even more so since we know this is being called
        // on each segment). We optimize what we can, by first collecting the matching
        // entries under a shared lock. This is nice since the expensive prefix match
        // won't block concurrent gets.
        pub fn delPrefix(self: *Self, allocator: Allocator, prefix: []const u8) !usize {
            const io = self.io;
            var matching: std.ArrayList(*Entry) = .empty;
            defer matching.deinit(allocator);

            self.mutex.lockSharedUncancelable(io);
            var it = self.lookup.iterator();
            while (it.next()) |map_entry| {
                if (std.mem.startsWith(u8, map_entry.key_ptr.*, prefix)) {
                    try matching.append(allocator, map_entry.value_ptr.*);
                }
            }
            self.mutex.unlockShared(io);

            const entries = matching.items;
            if (entries.len == 0) {
                return 0;
            }

            var lookup = &self.lookup;
            self.mutex.lockUncancelable(io);
            for (entries) |entry| {
                // Use saturating subtraction to handle race condition where
                // entry was already deleted between shared and exclusive lock
                if (lookup.remove(entry.key)) {
                    self.size = self.size -| entry._size;
                }
            }
            self.mutex.unlock(io);

            // list and entry have their own thread safety
            var list = &self.list;
            for (entries) |entry| {
                list.remove(io, entry._node);
                entry.release();
            }

            return entries.len;
        }
    };
}
