const std = @import("std");
const common = @import("common.zig");

pub const Headers = @This();

pub const Header = common.Header;

/// HTTP header iterator for parsing raw header bytes.
///
/// This is useful when you have raw HTTP protocol bytes and need to parse headers.
/// For iterating over headers from a backend, use the `entries()` method which
/// returns the vtable-based `Iterator`.
pub const HeaderIterator = std.http.HeaderIterator;

backend_ctx: ?*anyopaque = null,
vtable: ?*const VTable = null,

/// Whether this Headers instance is read-only (from request)
read_only: bool = true,

pub const VTable = struct {
    get: *const fn (ctx: *anyopaque, name: []const u8) ?[]const u8,
    has: *const fn (ctx: *anyopaque, name: []const u8) bool,
    set: *const fn (ctx: *anyopaque, name: []const u8, value: []const u8) void,
    append: *const fn (ctx: *anyopaque, name: []const u8, value: []const u8) void,
    iterate: *const fn (ctx: *anyopaque) ?Iterator,
};

// --- Headers Methods --- //

/// Returns true if this Headers instance is read-only (from request).
pub fn isReadOnly(self: *const Headers) bool {
    return self.read_only;
}

/// Returns the value of the header with the specified name.
pub fn get(self: *const Headers, name: []const u8) ?[]const u8 {
    if (self.vtable) |vt| {
        if (self.backend_ctx) |ctx| {
            return vt.get(ctx, name);
        }
    }
    return null;
}

/// Returns whether a header with the specified name exists.
pub fn has(self: *const Headers, name: []const u8) bool {
    if (self.vtable) |vt| {
        if (self.backend_ctx) |ctx| {
            return vt.has(ctx, name);
        }
    }
    return false;
}

/// Appends a new value onto an existing header (response only, no-op for request).
///
/// https://developer.mozilla.org/en-US/docs/Web/API/Headers/append
pub fn append(self: *Headers, name: []const u8, value: []const u8) void {
    if (self.read_only) return;
    if (self.vtable) |vt| {
        if (self.backend_ctx) |ctx| {
            vt.append(ctx, name, value);
        }
    }
}

/// Sets a header value (response only, no-op for request).
///
/// https://developer.mozilla.org/en-US/docs/Web/API/Headers/set
pub fn set(self: *Headers, name: []const u8, value: []const u8) void {
    if (self.read_only) return;
    if (self.vtable) |vt| {
        if (self.backend_ctx) |ctx| {
            vt.set(ctx, name, value);
        }
    }
}

/// Deletes a header. Note: Most backends don't support header deletion.
///
/// https://developer.mozilla.org/en-US/docs/Web/API/Headers/delete
pub fn delete(self: *Headers, name: []const u8) void {
    _ = self;
    _ = name;
    // Most backends don't support deletion - no-op
}

/// Returns an iterator over all key/value pairs.
pub fn entries(self: *const Headers) ?Iterator {
    if (self.vtable) |vt| {
        if (self.backend_ctx) |ctx| {
            return vt.iterate(ctx);
        }
    }
    return null;
}

/// Executes a provided function once for each header.
///
/// https://developer.mozilla.org/en-US/docs/Web/API/Headers/forEach
pub fn forEach(self: *const Headers, callback: *const fn (value: []const u8, key: []const u8) void) void {
    if (self.entries()) |*iter| {
        var it = iter.*;
        while (it.next()) |entry| {
            callback(entry.value, entry.name);
        }
    }
}

pub const Iterator = struct {
    backend_ctx: ?*anyopaque = null,
    nextFn: ?*const fn (ctx: *anyopaque) ?Header = null,

    /// Returns the next header, or null if iteration is complete.
    pub fn next(self: *Iterator) ?Header {
        if (self.nextFn) |nextFunc| {
            if (self.backend_ctx) |ctx| {
                return nextFunc(ctx);
            }
        }
        return null;
    }
};

// --- Builder --- //
pub const Builder = struct {
    backend_ctx: ?*anyopaque = null,
    vtable: ?*const VTable = null,
    read_only: bool = true,

    pub fn build(self: Builder) Headers {
        return .{
            .backend_ctx = self.backend_ctx,
            .vtable = self.vtable,
            .read_only = self.read_only,
        };
    }
};
