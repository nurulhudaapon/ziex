//! Common types for the app module.
//! These types are backend-independent and can be used with any HTTP server.
//!
//! This module re-exports types from `std.http` where available for consistency
//! with Zig's standard library.

const std = @import("std");

// --- HTTP Header (from std.http) --- //

/// HTTP header name/value pair - re-exported from std.http.Header for consistency.
///
/// Fields:
/// - `name`: The header name (e.g., "Content-Type", "Authorization")
/// - `value`: The header value
///
/// **Zig Note:** This uses `name` (as per RFC 7230) rather than `key`.
pub const Header = std.http.Header;

/// Alias for backward compatibility.
/// @deprecated Use `Header` instead.
pub const Entry = Header;

/// HTTP header iterator for parsing raw header bytes.
/// Re-exported from std.http.HeaderIterator for convenience.
///
/// Useful for parsing HTTP headers from raw bytes. Initializes with `init(bytes)`
/// and iterates via `next()` returning `?Header`.
pub const HeaderIterator = std.http.HeaderIterator;

/// Entry type for multipart form data (includes optional filename).
pub const MultiFormEntry = struct {
    key: []const u8,
    value: []const u8,
    filename: ?[]const u8,
};

// --- HTTP Method (from std.http) --- //
// https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods

/// HTTP request methods - re-exported from std.http.Method for convenience.
///
/// https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods
///
/// Includes useful methods:
/// - `requestHasBody()`: Returns true if request of this method can have a body
/// - `responseHasBody()`: Returns true if response to this method can have a body
/// - `safe()`: Returns true if this method doesn't alter server state
/// - `idempotent()`: Returns true if identical requests have the same effect
/// - `cacheable()`: Returns true if response can be cached
///
/// **Note:** Unlike some HTTP libraries, std.http.Method does not have an "OTHER"
/// variant for unknown methods. All standard HTTP methods are supported.
pub const Method = std.http.Method;

// --- HTTP Version (from std.http) --- //

/// HTTP protocol versions - re-exported from std.http.Version for convenience.
///
/// Values:
/// - `@"HTTP/1.0"`: HTTP/1.0 protocol
/// - `@"HTTP/1.1"`: HTTP/1.1 protocol
pub const Version = std.http.Version;

/// Alias for backward compatibility.
/// @deprecated Use `Version` instead.
pub const Protocol = Version;

// --- Cookie Types --- //

/// Cookie accessor - parses cookies from the Cookie header.
///
/// **Zig Note:** This is an extension type not present in the web standard.
/// In browsers, cookies are accessed via `document.cookie`.
pub const Cookies = struct {
    header_value: []const u8,

    pub fn get(self: Cookies, name: []const u8) ?[]const u8 {
        var it = std.mem.splitScalar(u8, self.header_value, ';');
        while (it.next()) |kv| {
            const trimmed = std.mem.trimLeft(u8, kv, " ");
            if (name.len >= trimmed.len) continue;
            if (!std.mem.startsWith(u8, trimmed, name)) continue;
            if (trimmed[name.len] != '=') continue;
            return trimmed[name.len + 1 ..];
        }
        return null;
    }

    pub fn getAs(self: Cookies, name: []const u8, comptime T: type) ?T {
        var it = std.mem.splitScalar(u8, self.header_value, ';');
        while (it.next()) |kv| {
            const trimmed = std.mem.trimLeft(u8, kv, " ");
            if (name.len >= trimmed.len) continue;
            if (!std.mem.startsWith(u8, trimmed, name)) continue;
            if (trimmed[name.len] != '=') continue;
            const str = trimmed[name.len + 1 ..];

            return switch (@typeInfo(T)) {
                .pointer => |p| switch (p.size) {
                    .Slice => if (p.child == u8 and p.is_const) str
                              else @compileError("Cookies.getAs: only []const u8 is supported, got " ++ @typeName(T)),
                    else => @compileError("Cookies.getAs: only []const u8 is supported, got " ++ @typeName(T)),
                },
                .int   => std.fmt.parseInt(T, str, 10) catch return null,
                .float => std.fmt.parseFloat(T, str) catch return null,
                .bool  => if (std.mem.eql(u8, str, "true")  or std.mem.eql(u8, str, "1")) true
                     else if (std.mem.eql(u8, str, "false") or std.mem.eql(u8, str, "0")) false
                     else return null,
                .@"enum"  => std.meta.stringToEnum(T, str) orelse return null,
                .@"struct", .@"union" => @compileError("Cookies.getAs: use getJson for struct/union types"),
                else => @compileError("Cookies.getAs: unsupported type " ++ @typeName(T)),
            };
        }
        return null;
    }
};

/// Options for setting cookies.
///
/// https://developer.mozilla.org/en-US/docs/Web/HTTP/Cookies
pub const CookieOptions = struct {
    /// Specifies the URL path that must exist in the requested URL.
    path: []const u8 = "",
    /// Specifies allowed hosts to receive the cookie.
    domain: []const u8 = "",
    /// Indicates the maximum lifetime of the cookie in seconds.
    max_age: ?i32 = null,
    /// Indicates that the cookie is sent only over HTTPS.
    secure: bool = false,
    /// Forbids JavaScript from accessing the cookie.
    http_only: bool = false,
    /// Indicates the cookie should be stored using partitioned storage.
    partitioned: bool = false,
    /// Controls whether the cookie is sent with cross-site requests.
    same_site: ?SameSite = null,

    pub const SameSite = enum {
        lax,
        strict,
        none,
    };
};

// --- HTTP Status (from std.http) --- //
// https://developer.mozilla.org/en-US/docs/Web/HTTP/Status

/// HTTP status codes - re-exported from std.http.Status for convenience.
///
/// https://developer.mozilla.org/en-US/docs/Web/HTTP/Status
///
/// Includes useful methods:
/// - `phrase()`: Returns the status message (e.g., "OK", "Not Found")
/// - `class()`: Returns the status class (.informational, .success, .redirect, .client_error, .server_error)
pub const HttpStatus = std.http.Status;

/// Returns the status message (phrase) for an HTTP status code.
/// Uses the standard library's Status.phrase() method.
pub fn statusCodeToText(code: u16) []const u8 {
    const status: HttpStatus = @enumFromInt(code);
    return status.phrase() orelse "Unknown";
}

// --- Content Types (MIME types) --- //
// https://developer.mozilla.org/en-US/docs/Web/HTTP/Basics_of_HTTP/MIME_types

/// Common MIME content types.
///
/// https://developer.mozilla.org/en-US/docs/Web/HTTP/Basics_of_HTTP/MIME_types/Common_types
///
/// **Zig Note:** The standard library does not provide a ContentType enum.
/// This enum uses the actual MIME type string as the tag name for convenience.
pub const ContentType = enum {
    // Application types
    @"application/gzip",
    @"application/javascript",
    @"application/json",
    @"application/octet-stream",
    @"application/pdf",
    @"application/wasm",
    @"application/xhtml+xml",
    @"application/xml",
    @"application/x-www-form-urlencoded",

    // Audio types
    @"audio/aac",
    @"audio/mpeg",
    @"audio/ogg",
    @"audio/wav",
    @"audio/webm",

    // Font types
    @"font/otf",
    @"font/ttf",
    @"font/woff",
    @"font/woff2",

    // Image types
    @"image/avif",
    @"image/bmp",
    @"image/gif",
    @"image/jpeg",
    @"image/png",
    @"image/svg+xml",
    @"image/tiff",
    @"image/webp",

    // Multipart types
    @"multipart/form-data",

    // Text types
    @"text/css",
    @"text/csv",
    @"text/html",
    @"text/javascript",
    @"text/plain",
    @"text/xml",

    // Video types
    @"video/mp4",
    @"video/mpeg",
    @"video/ogg",
    @"video/webm",
    @"video/x-msvideo",

    /// Returns the MIME type string.
    pub fn toString(self: ContentType) []const u8 {
        return @tagName(self);
    }
};

// --- Re-exports from std.http for convenience --- //

/// HTTP content encoding - re-exported from std.http.ContentEncoding.
///
/// Values: zstd, gzip, deflate, compress, identity
pub const ContentEncoding = std.http.ContentEncoding;

/// HTTP transfer encoding - re-exported from std.http.TransferEncoding.
///
/// Values: chunked, none
pub const TransferEncoding = std.http.TransferEncoding;

/// HTTP connection type - re-exported from std.http.Connection.
///
/// Values: keep_alive, close
pub const Connection = std.http.Connection;
