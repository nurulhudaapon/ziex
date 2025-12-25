const std = @import("std");

var ts_allocator: ?std.mem.Allocator = null;

var alloc_registry: ?std.AutoHashMap(usize, usize) = null;

var alloc_mutex: std.Thread.Mutex = .{};

var _free_fn: ?*const fn (?*anyopaque) callconv(.c) void = null;

pub fn free_fn() *const fn (?*anyopaque) callconv(.c) void {
    if (_free_fn == null) {
        _free_fn = std.c.free;
    }
    return _free_fn.?;
}

/// Set the allocator used by the library.
///
/// By default, Tree-sitter uses the standard libc allocation functions,
/// but aborts the process when an allocation fails. This function lets
/// you supply alternative allocation functions at runtime.
///
/// If you call this function after the library has already been used,
/// then you must ensure that either:
///  1. All the existing objects have been freed.
///  2. The new allocator shares its state with the old one, so it is
///     capable of freeing memory that was allocated by the old allocator.
///
/// When you no longer need the allocator, you must call `setAllocator(null)`
/// to reset it and free the allocated memory.
pub fn setAllocator(allocator: ?std.mem.Allocator) void {
    if (allocator) |alloc| {
        ts_allocator = alloc;
        alloc_registry = .init(ts_allocator.?);
        _free_fn = free;
        ts_set_allocator(malloc, calloc, realloc, free);
    } else {
        ts_allocator = null;
        if (alloc_registry != null) {
            alloc_registry.?.deinit();
            alloc_registry = null;
        }
        _free_fn = std.c.free;
        ts_set_allocator(null, null, null, null);
    }
}

fn malloc(size: usize) callconv(.c) ?*anyopaque {
    alloc_mutex.lock();
    defer alloc_mutex.unlock();

    if (ts_allocator.?.alloc(u8, size)) |slice| {
        alloc_registry.?.put(@intFromPtr(slice.ptr), slice.len) catch {
            ts_allocator.?.free(slice);
            return null;
        };

        return @ptrCast(slice);
    } else |_| {
        return null;
    }
}

fn calloc(nmemb: usize, size: usize) callconv(.c) ?*anyopaque {
    alloc_mutex.lock();
    defer alloc_mutex.unlock();

    if (ts_allocator.?.alloc(u8, nmemb * size)) |new_mem| {
        alloc_registry.?.put(@intFromPtr(new_mem.ptr), new_mem.len) catch {
            ts_allocator.?.free(new_mem);
            return null;
        };

        @memset(new_mem, 0);

        return @ptrCast(new_mem);
    } else |_| {
        return null;
    }
}

fn realloc(ptr: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque {
    const old_ptr = ptr orelse malloc(size);

    alloc_mutex.lock();
    defer alloc_mutex.unlock();

    const old_size = alloc_registry.?.get(@intFromPtr(old_ptr)) orelse return malloc(size);
    var old_mem: []u8 = undefined;
    old_mem.ptr = @ptrCast(old_ptr);
    old_mem.len = old_size;

    if (ts_allocator.?.realloc(old_mem, size)) |new_mem| {
        _ = alloc_registry.?.remove(@intFromPtr(old_ptr));

        if (new_mem.len == 0) return null;

        alloc_registry.?.put(@intFromPtr(new_mem.ptr), new_mem.len) catch {
            ts_allocator.?.free(new_mem);
            return null;
        };

        return @ptrCast(new_mem);
    } else |_| {
        return null;
    }

    return malloc(size);
}

fn free(ptr: ?*anyopaque) callconv(.c) void {
    alloc_mutex.lock();
    defer alloc_mutex.unlock();

    const old_ptr = ptr orelse return;

    if (alloc_registry.?.fetchRemove(@intFromPtr(old_ptr))) |mem| {
        var slice: []u8 = undefined;
        slice.ptr = @ptrCast(old_ptr);
        slice.len = mem.value;
        ts_allocator.?.free(slice);
    }
}

extern fn ts_set_allocator(
    new_malloc: ?*const fn (size: usize) callconv(.c) ?*anyopaque,
    new_calloc: ?*const fn (nmemb: usize, size: usize) callconv(.c) ?*anyopaque,
    new_realloc: ?*const fn (ptr: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque,
    new_free: ?*const fn (ptr: ?*anyopaque) callconv(.c) void,
) void;
