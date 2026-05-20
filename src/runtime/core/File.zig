//! Represents an uploaded file from a multipart form submission.
//!
//! The `data` field is a type-erased `std.Io.AnyReader` so call-site code
//! is written against the reader interface today and will continue to compile
//! unchanged when a streaming multipart parser is introduced in the future.
//! Currently the reader is backed by the in-memory request body bytes.

const std = @import("std");

pub const File = @This();

/// Original filename as reported by the browser (empty string when absent).
name: []const u8 = "",

/// MIME type of the file, e.g. `"image/png"` (empty string when unknown).
content_type: []const u8 = "",

/// File size in bytes.
/// For future streaming readers this may be 0 if the size is not yet known.
size: usize = 0,

/// Reader interface for the file content.
/// Do not retain this value after the action handler returns; the backing
/// memory belongs to the request arena.
data: std.Io.AnyReader = emptyReader(),

/// Build a File backed by an in-memory byte slice.
/// `fbs_alloc` must outlive the returned File (use the request arena).
pub fn fromBytes(
    bytes: []const u8,
    name: []const u8,
    content_type: []const u8,
    fbs_alloc: std.mem.Allocator,
) File {
    const fbs = fbs_alloc.create(std.Io.FixedBufferStream([]const u8)) catch return .{
        .name = name,
        .content_type = content_type,
        .size = bytes.len,
    };
    fbs.* = std.Io.fixedBufferStream(bytes);
    return .{
        .name = name,
        .content_type = content_type,
        .size = bytes.len,
        .data = fbs.reader().any(),
    };
}

// ── Internal ────────────────────────────────────────────────────────────────

fn emptyReadFn(_: *const anyopaque, _: []u8) anyerror!usize {
    return 0;
}

var empty_ctx: u8 = 0;

fn emptyReader() std.Io.AnyReader {
    return .{ .context = &empty_ctx, .readFn = &emptyReadFn };
}
