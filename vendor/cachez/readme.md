A thread-safe, expiration-aware, LRU(ish) cache for Zig

## Zig Version
This is for Zig 0.16.0. Use the [zig-0.15](https://github.com/karlseguin/cached.zig/tree/zig-0.15) branch for Zig 0.15 or the [dev](https://github.com/karlseguin/cached.zig/tree/dev) which may or may not be up to date with zig dev.

## Example

```zig
// package available using Zig's built-in package manager
const user_cache = @import("cache");

var user_cache = try cache.Cache(User).init(io, allocator, .{.max_size = 10000});
defer user_cache.deinit();

try user_cache.put("user1", user1, .{.ttl = 300});
...

if (user_cache.get("user1")) |entry| {
    defer entry.release();
    const user1 = entry.value;
} else {
    // not in the cache
}

// del will return true if the item existed
_ = user_cache.del("user1");
```

`get` will return `null` if the key is not found, or if the entry associated with the key has expired. If the entry has expired, it will be removed.

`getEntry` can be used to return the entry even if it has expired. While `getEntry` will return en expired item, it will not promote a expired item in the recency list. The main purpose is to allow the caller to serve a stale value while fetching a new one.

In either case, the entry's `ttl(std.Io) i64` method can be used to return the number of seconds until the entry expires. This will be negative if the entry has already expired. The `expired(std.Io) bool` method will return `true` if the entry is expired. (Both of these methods take an `std.Io` parameter as to avoid having to store a reference in every `Entry` instance)

`release` must be called on the returned entry.

## Implementation
This is a typical LRU cache which combines a hashmap to lookup values and doubly linked list to track recency. 

To improve throughput, the cache is divided into a configured number of segments (defaults to 8). Locking only happens at the segment level. Furthermore, items are only promoted to the head of the recency linked list after a configured number of gets. This not only reduces the locking on the linked list, but also introduces a frequency bias to the eviction policy (which I think is welcome addition).

The downside of this approach is that size enforcement and the eviction policy is done on a per-segment basis. Given a `max_size` of 8000 and a `segment_count` of 8, each segment will enforce its own `max_size` of 1000 and maintain its own recency list. Should keys be poorly distributed across segments, the cache will only reach a fraction of its configured max size. Only least-recently used items within a segment are considered for eviction.

## Configuration
The 2nd argument to init is a `cache.Config`. It's fields with default values are:

```zig
{
    // The max size of the cache. By default, each value has a size of 1. Thus
    // given a `max_size` of 5000, the cache can hold up to 5000 items before
    // having to evict entries. The size of a value can be set when using 
    // `cache.put` or `cache.fetch`.
    max_size: u32 = 8000,

    // The number of segments to use. Must be a power of 2. 
    // A value of 1 is valid.
    segment_count: u16 = 8,

    // The number of times get or getEntry must be called on a key before 
    // it's promoted to the head of the recency list
    gets_per_promote: u8 = 5,

    // When a segment is full, the ratio of the segment's max_size to free.
    shrink_ratio: f32 = 0.2,
}
```
Given the above, each segment will enforce its own `max_size` of 1000 (i.e. `8000 / 8`). When a segment grows beyond 1000, entries will be removed until its size becomes less than or equal to 800 (i.e. `1000 - (1000 * 0.2)`)

## Put
The `cache.put(key: []const u8, value: T, config: cache.PutConfig) !void` has a number of consideration.

First, the key will be cloned and managed by the cache. The caller does not have to guarantee its validity after `put` returns.

The third parameter is a `cache.PutConfig`: 

```zig
{
    .ttl: u32 = 300,
    .size: u32 = 1,
}
```
`ttl` is the length, in seconds, to keep the value in the cache.

`size` is the size of the value. This doesn't have to be the actual memory used by the value being cached. In many cases, the default of `1` is reasonable. However, if enforcement of the memory used by the cache is important, giving an approximate size (as memory usage or as a weighted value) will help. For example, if you're caching a string, the length of the string could make a reasonable argument for `size`. 

If `T` defines a **public** method `size() u32`, this value will be used instead of the above configured `size`. This can be particularly useful with the `fetch` method.


## Fetch
`cache.fetch` can be used to combine `get` and `put` by providing a custom function to load a missing value:

```zig
const user = try cache.fetch(FetchState, "user1", loadUser, .{user_id: 1}, .{.ttl = 300});
...

const FetchState = struct {
    user_id: u32,
};

fn loadUser(state: FetchState, key: []const u8) !?User {
    const user_id = state.user_id
    const user = ... // load a user from the DB?
    return user;
}
```

Because Zig doesn't have closures, and because your custom function will likely need data to load the missing value, you provide a custom `state` type and value which will be passed to your function. They cache key is also passed, which, in simple cases, might be all your function needs to load data (in such cases, a `void` state can be used).

The last parameter to `fetch` is the same as the last parameter to `put`.

Fetch  does not do duplicate function call suppression. Concurrent calls to `fetch` using the same key can result in multiple functions to your callback functions. In other words, fetch is vulnerable to the thundering herd problem. Considering using [singleflight.zig](https://github.com/karlseguin/singleflight.zig) within your fetch callback.

The `size` of the value might not be known until the value is fetched, this makes passing `size` into fetch impossible. If `T` defines a **public** method `size() u32`, then `T.size(value)` will be called to get the size.

## Entry Thread Safety
It's possible for one thread to `get` an entry, while another thread deletes it. This deletion could be explicit (a call to `cache.del` or replacing a value with `cache.put`) or implicit (a call to `cache.put` causing the cache to free memory). To ensure that deleted entries can safely be used by the application, atomic reference counting is used. While a deleted entry is immediately removed from the cache, it remains valid until all references are removed.

This is why `release` must be called on the entry returned by `get` and `getEntry`. Calling `release` multiple times on a single entry will break the cache.

## removedFromCache notification
If `T` defines a **public** method `removedFromCache`, `T.removedFromCache(Allocator)` will be called when all references are removed but before the entry is destroyed. `removedFromCache` will be called regardless of why the entry was removed.

The `Allocator` passed to `removedFromCache` is the `Allocator` that the cache was created with - this may or may not be an allocator that is meaningful to the value.

## delPrefix
`cache.delPrefix` can be used to delete any entry that starts with the specified prefix. This requires an O(N) scan through the cache. However, some optimizations are done to limit the amount of write-lock this places on the cache.
