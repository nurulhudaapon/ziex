const std = @import("std");
const httpz = @import("httpz");

const Allocator = std.mem.Allocator;
const Conn = httpz.websocket.Conn;

/// Subscriber data stored alongside each WebSocket connection
pub const SubscriberData = struct {
    /// Set of topics this connection is subscribed to
    topics: std.StringHashMapUnmanaged(void) = .{},
    /// Whether publish() sends to self as well
    publish_to_self: bool = false,
    /// Reference to the connection
    conn: *Conn,
    /// Allocator for topic storage
    allocator: Allocator,

    pub fn init(conn: *Conn, allocator: Allocator) SubscriberData {
        return .{
            .conn = conn,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SubscriberData) void {
        // Free all topic keys
        var iter = self.topics.keyIterator();
        while (iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.topics.deinit(self.allocator);
    }

    pub fn subscribe(self: *SubscriberData, topic: []const u8) void {
        if (self.topics.contains(topic)) return;

        const owned_topic = self.allocator.dupe(u8, topic) catch return;
        self.topics.put(self.allocator, owned_topic, {}) catch {
            self.allocator.free(owned_topic);
            return;
        };

        // Also register in global registry
        getPubSub().addSubscriber(topic, self);
    }

    pub fn unsubscribe(self: *SubscriberData, topic: []const u8) void {
        // Remove from global registry first
        getPubSub().removeSubscriber(topic, self);

        // Then remove from local set
        if (self.topics.fetchRemove(topic)) |entry| {
            self.allocator.free(entry.key);
        }
    }

    pub fn unsubscribeAll(self: *SubscriberData) void {
        var iter = self.topics.keyIterator();
        while (iter.next()) |key| {
            getPubSub().removeSubscriber(key.*, self);
        }
        self.deinit();
        self.topics = .{};
    }

    pub fn isSubscribed(self: *SubscriberData, topic: []const u8) bool {
        return self.topics.contains(topic);
    }

    pub fn getSubscriptions(self: *SubscriberData, allocator: Allocator) []const []const u8 {
        var result: std.ArrayListUnmanaged([]const u8) = .{};
        var iter = self.topics.keyIterator();
        while (iter.next()) |key| {
            result.append(allocator, key.*) catch continue;
        }
        return result.toOwnedSlice(allocator) catch &.{};
    }
};

/// A set of subscribers (pointers to SubscriberData)
const SubscriberSet = std.AutoHashMapUnmanaged(*SubscriberData, void);

/// Global pub/sub registry - maps topics to subscriber sets
pub const PubSub = struct {
    /// Maps topic names to sets of subscribers
    topics: std.StringHashMapUnmanaged(SubscriberSet) = .{},
    /// RwLock for concurrent access (readers don't block each other)
    lock: std.Io.RwLock = .init,
    /// Allocator for topic keys and sets
    allocator: Allocator,

    /// Global singleton instance
    var instance: ?*PubSub = null;

    /// Get or create the global PubSub instance
    pub fn getInstance(allocator: Allocator) *PubSub {
        // Use @atomicLoad for lock-free fast path
        if (@atomicLoad(?*PubSub, &instance, .acquire)) |ps| {
            return ps;
        }

        // Slow path - create instance
        const ps = allocator.create(PubSub) catch @panic("Failed to create PubSub");
        ps.* = PubSub{
            .allocator = allocator,
        };

        // Atomically set instance
        @atomicStore(?*PubSub, &instance, ps, .release);
        return ps;
    }

    /// Add a subscriber to a topic
    pub fn addSubscriber(self: *PubSub, topic: []const u8, subscriber: *SubscriberData) void {
        self.lock.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.lock.unlock(std.Io.Threaded.global_single_threaded.io());

        const result = self.topics.getOrPut(self.allocator, topic) catch return;
        if (!result.found_existing) {
            // Create new topic entry with owned key
            result.key_ptr.* = self.allocator.dupe(u8, topic) catch return;
            result.value_ptr.* = .{};
        }
        result.value_ptr.put(self.allocator, subscriber, {}) catch return;
    }

    /// Remove a subscriber from a topic
    pub fn removeSubscriber(self: *PubSub, topic: []const u8, subscriber: *SubscriberData) void {
        self.lock.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.lock.unlock(std.Io.Threaded.global_single_threaded.io());

        if (self.topics.getPtr(topic)) |subscriber_set| {
            _ = subscriber_set.remove(subscriber);

            // Clean up empty topics
            if (subscriber_set.count() == 0) {
                subscriber_set.deinit(self.allocator);
                if (self.topics.fetchRemove(topic)) |entry| {
                    self.allocator.free(entry.key);
                }
            }
        }
    }

    /// Publish a message to all subscribers of a topic
    /// Returns the number of messages sent
    pub fn publish(self: *PubSub, sender: ?*SubscriberData, topic: []const u8, message: []const u8) usize {
        // Use read lock - multiple publishers can run concurrently
        self.lock.lockSharedUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.lock.unlockShared(std.Io.Threaded.global_single_threaded.io());

        var sent: usize = 0;

        if (self.topics.get(topic)) |subscriber_set| {
            var iter = subscriber_set.keyIterator();
            while (iter.next()) |sub_ptr| {
                const subscriber = sub_ptr.*;

                // Skip sender unless publish_to_self is enabled
                if (sender) |s| {
                    if (subscriber == s and !s.publish_to_self) {
                        continue;
                    }
                }

                subscriber.conn.write(message) catch continue;
                sent += 1;
            }
        }

        return sent;
    }

    /// Get the number of subscribers for a topic
    pub fn subscriberCount(self: *PubSub, topic: []const u8) usize {
        self.lock.lockSharedUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.lock.unlockShared(std.Io.Threaded.global_single_threaded.io());

        if (self.topics.get(topic)) |subscriber_set| {
            return subscriber_set.count();
        }
        return 0;
    }
};

/// Get the global PubSub instance
pub fn getPubSub() *PubSub {
    return PubSub.getInstance(std.heap.page_allocator);
}
