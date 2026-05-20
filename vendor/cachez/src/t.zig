const std = @import("std");
const cache = @import("cache.zig");
const List = @import("list.zig").List;

pub const io = std.testing.io;
pub const expect = std.testing.expect;
pub const allocator = std.testing.allocator;

pub const expectEqual = std.testing.expectEqual;
pub const expectError = std.testing.expectError;
pub const expectString = std.testing.expectEqualStrings;

pub const Entry = cache.Entry(i32);

pub fn initCache() cache.Cache(i32) {
    return cache.Cache(i32).init(io, allocator, .{ .segment_count = 2 }) catch unreachable;
}
