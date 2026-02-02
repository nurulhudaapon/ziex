//! The Response interface of the Fetch API represents the response to a request.
//!
//! You can create a new Response object using the Response.Builder, but you are more likely
//! to encounter a Response object being returned as the result of another API operation—for
//! example, a page handler context or a fetch() call.
//!
//! This module is backend-agnostic. The actual implementation is provided via vtable.
//!
//! https://developer.mozilla.org/en-US/docs/Web/API/Response

const std = @import("std");
const common = @import("common.zig");

pub const Response = @This();

// Re-export common types for convenience
pub const Cookies = common.Cookies;
pub const CookieOptions = common.CookieOptions;
pub const ContentType = common.ContentType;
pub const HttpStatus = common.HttpStatus;

/// The type of the response.
///
/// https://developer.mozilla.org/en-US/docs/Web/API/Response/type
///
/// **Values:**
/// - `basic`: Normal, same origin response, with all headers exposed except "Set-Cookie".
/// - `cors`: Response was received from a valid cross-origin request.
/// - `default`: Default response type (used when response type is not explicitly set).
/// - `error`: Network error. No useful information describing the error is available.
/// - `opaque`: Response for "no-cors" request to cross-origin resource.
/// - `opaqueredirect`: The fetch request was made with redirect: "manual".
pub const ResponseType = enum {
    basic,
    cors,
    default,
    @"error",
    @"opaque",
    opaqueredirect,
};

// --- Instance Properties --- //
// https://developer.mozilla.org/en-US/docs/Web/API/Response#instance_properties

/// A ReadableStream of the body contents.
///
/// https://developer.mozilla.org/en-US/docs/Web/API/Response/body
///
/// **Zig Note:** In the web standard, this is a ReadableStream. In this implementation,
/// it is represented as `[]const u8` (a byte slice) for simplicity.
body: []const u8 = "",

/// Stores a boolean value that declares whether the body has been used in a response yet.
///
/// https://developer.mozilla.org/en-US/docs/Web/API/Response/bodyUsed
bodyUsed: bool = false,

/// The Headers object associated with the response.
///
/// https://developer.mozilla.org/en-US/docs/Web/API/Response/headers
headers: Headers = .{},

/// A boolean indicating whether the response was successful (status in the range 200–299) or not.
///
/// https://developer.mozilla.org/en-US/docs/Web/API/Response/ok
ok: bool = true,

/// Indicates whether or not the response is the result of a redirect
/// (that is, its URL list has more than one entry).
///
/// https://developer.mozilla.org/en-US/docs/Web/API/Response/redirected
redirected: bool = false,

/// The status code of the response (e.g., 200 for a success).
///
/// https://developer.mozilla.org/en-US/docs/Web/API/Response/status
status: u16 = 200,

/// The status message corresponding to the status code (e.g., "OK" for 200).
///
/// https://developer.mozilla.org/en-US/docs/Web/API/Response/statusText
statusText: []const u8 = "OK",

/// The type of the response (e.g., basic, cors).
///
/// https://developer.mozilla.org/en-US/docs/Web/API/Response/type
///
/// **Zig Note:** In the web standard, this is a string. In this implementation,
/// it is represented as a `ResponseType` enum for type safety.
type: ResponseType = .default,

/// The URL of the response.
///
/// https://developer.mozilla.org/en-US/docs/Web/API/Response/url
url: []const u8 = "",

// --- Internal Fields (not part of web standard) --- //

/// Arena allocator for response-scoped allocations.
///
/// **Zig Note:** This is an internal field not present in the web standard.
/// Used for memory management in the Zig implementation.
arena: std.mem.Allocator,

/// Backend-specific context pointer (null for WASM/client-side).
///
/// **Zig Note:** This is an internal field not present in the web standard.
/// Provides the vtable pattern for backend abstraction.
backend_ctx: ?*anyopaque = null,

/// VTable for backend-specific operations.
///
/// **Zig Note:** This is an internal field not present in the web standard.
/// Allows different HTTP server backends to implement response operations.
vtable: ?*const VTable = null,

/// VTable interface for backend-specific response operations.
///
/// **Zig Note:** This is an internal type not present in the web standard.
pub const VTable = struct {
    /// Sets the response status code.
    setStatus: *const fn (ctx: *anyopaque, code: u16) void,
    /// Sets the response body.
    setBody: *const fn (ctx: *anyopaque, content: []const u8) void,
    /// Sets a header.
    setHeader: *const fn (ctx: *anyopaque, name: []const u8, value: []const u8) void,
    /// Gets a writer for streaming.
    getWriter: *const fn (ctx: *anyopaque) *std.Io.Writer,
    /// Writes a chunk for chunked transfer.
    writeChunk: *const fn (ctx: *anyopaque, data: []const u8) anyerror!void,
    /// Clears the response writer/buffer.
    clearWriter: *const fn (ctx: *anyopaque) void,
    /// Sets a cookie on the response.
    setCookie: *const fn (ctx: *anyopaque, name: []const u8, value: []const u8, opts: CookieOptions) anyerror!void,
};

// --- Methods --- //

/// Sets the HTTP status code using an HttpStatus enum.
///
/// **Zig Note:** This is an extension method not present in the web standard Response
/// interface (which has read-only status). This method updates the backend response.
/// The local `status`, `statusText`, and `ok` fields reflect the initial state;
/// use the backend for the source of truth after mutation.
pub fn setStatus(self: *const Response, stat: HttpStatus) void {
    if (self.vtable) |vt| {
        if (self.backend_ctx) |ctx| {
            vt.setStatus(ctx, @intFromEnum(stat));
        }
    }
}

/// Sets the HTTP status code using a raw u16 value.
///
/// **Zig Note:** This is an extension method not present in the web standard Response
/// interface (which has read-only status). This method updates the backend response.
pub fn setStatusCode(self: *const Response, code: u16) void {
    if (self.vtable) |vt| {
        if (self.backend_ctx) |ctx| {
            vt.setStatus(ctx, code);
        }
    }
}

/// Sets the response body directly.
///
/// **Zig Note:** This is an extension method not present in the web standard Response
/// interface (which has read-only body). This method updates the backend response.
pub fn text(self: *const Response, content: []const u8) void {
    if (self.vtable) |vt| {
        if (self.backend_ctx) |ctx| {
            vt.setBody(ctx, content);
        }
    }
}

/// Sets the response body to a JSON string.
///
/// **Zig Note:** This is an extension method not present in the web standard Response
/// interface (which has read-only body). This method updates the backend response.
///
/// **Parameters:**
/// - `value`: The value to serialize as JSON.
/// - `options`: Optional JSON stringify options (whitespace, etc.).
pub fn json(self: *const Response, value: anytype, options: std.json.Stringify.Options) !void {
    self.setContentType(.@"application/json");

    if (self.writer()) |w| {
        const json_formatter = std.json.fmt(value, options);
        try json_formatter.format(w);
    }
}

/// Sets a header on the response.
///
/// **Zig Note:** This is an extension method. In the web standard, you would use
/// `response.headers.set(name, value)` on the Headers object instead.
pub fn setHeader(self: *const Response, name: []const u8, value: []const u8) void {
    if (self.vtable) |vt| {
        if (self.backend_ctx) |ctx| {
            vt.setHeader(ctx, name, value);
        }
    }
}

/// Sets the Content-Type header.
///
/// **Zig Note:** This is a convenience method not present in the web standard.
/// Equivalent to `setHeader("Content-Type", content_type.toString())`.
pub fn setContentType(self: *const Response, content_type: ContentType) void {
    self.setHeader("Content-Type", content_type.toString());
}

/// Creates a redirect response by setting the Location header and status code.
///
/// https://developer.mozilla.org/en-US/docs/Web/API/Response/redirect_static
///
/// **Zig Note:** In the web standard, `Response.redirect()` is a static method that
/// creates a new Response object. In this implementation, it modifies the current
/// response by setting the Location header and status code on the backend.
///
/// **Parameters:**
/// - `location`: The URL to redirect to.
/// - `redirect_status`: Optional status code (default: 302 Found).
pub fn redirect(self: *const Response, location: []const u8, redirect_status: ?u16) void {
    const code = redirect_status orelse 302;
    self.setStatusCode(code);
    self.setHeader("Location", location);
}

/// **Extension to Web Standard:**
/// Sets a cookie on the response.
///
/// https://developer.mozilla.org/en-US/docs/Web/HTTP/Cookies
///
/// **Parameters:**
/// - `name`: The cookie name.
/// - `value`: The cookie value.
/// - `options`: Optional cookie options (path, domain, max_age, secure, etc.).
pub fn setCookie(self: *const Response, name: []const u8, value: []const u8, options: ?CookieOptions) void {
    const opts = options orelse CookieOptions{};
    if (self.vtable) |vt| {
        if (self.backend_ctx) |ctx| {
            vt.setCookie(ctx, name, value, opts) catch {};
        }
    }
}

/// **Extension to Web Standard:**
/// Deletes a cookie by setting it with an expired max-age.
///
///
/// **Parameters:**
/// - `name`: The cookie name to delete.
/// - `options`: Optional cookie options (path and domain should match the original cookie).
pub fn deleteCookie(self: *const Response, name: []const u8, options: ?CookieOptions) void {
    var opts = options orelse CookieOptions{};
    opts.max_age = 0; // Setting max-age to 0 deletes the cookie
    self.setCookie(name, "", opts);
}

/// Gets the response writer for streaming content.
///
/// **Zig Note:** This is an extension method not present in the web standard.
/// Used for server-side streaming responses.
pub fn writer(self: *const Response) ?*std.Io.Writer {
    if (self.vtable) |vt| {
        if (self.backend_ctx) |ctx| {
            return vt.getWriter(ctx);
        }
    }
    return null;
}

/// Writes a chunk for chunked transfer encoding.
///
/// **Zig Note:** This is an extension method not present in the web standard.
/// Used for server-side streaming/chunked responses.
pub fn chunk(self: *const Response, data: []const u8) !void {
    if (self.vtable) |vt| {
        if (self.backend_ctx) |ctx| {
            try vt.writeChunk(ctx, data);
        }
    }
}

/// Clears the response writer/buffer.
///
/// **Zig Note:** This is an extension method not present in the web standard.
/// Used for server-side response management.
pub fn clearWriter(self: *const Response) void {
    if (self.vtable) |vt| {
        if (self.backend_ctx) |ctx| {
            vt.clearWriter(ctx);
        }
    }
}

// --- Headers --- //
// https://developer.mozilla.org/en-US/API/Headers

/// The Headers interface of the Fetch API allows you to perform various actions
/// on HTTP request and response headers.
///
/// https://developer.mozilla.org/en-US/docs/Web/API/Headers
///
/// **Zig Note:** This is a simplified implementation that delegates to the backend.
/// Not all methods from the web standard Headers interface are implemented.
pub const Headers = struct {
    backend_ctx: ?*anyopaque = null,
    vtable: ?*const HeadersVTable = null,

    pub const HeadersVTable = struct {
        get: *const fn (ctx: *anyopaque, name: []const u8) ?[]const u8,
        set: *const fn (ctx: *anyopaque, name: []const u8, value: []const u8) void,
        add: *const fn (ctx: *anyopaque, name: []const u8, value: []const u8) void,
    };

    /// Returns a String sequence of all the values of a header within a Headers
    /// object with a given name.
    ///
    /// https://developer.mozilla.org/en-US/docs/Web/API/Headers/get
    ///
    /// **Zig Note:** Returns `?[]const u8` instead of a string, returning `null`
    /// if the header is not found.
    pub fn get(self: *const Headers, name: []const u8) ?[]const u8 {
        if (self.vtable) |vt| {
            if (self.backend_ctx) |ctx| {
                return vt.get(ctx, name);
            }
        }
        return null;
    }

    /// Sets a new value for an existing header inside a Headers object,
    /// or adds the header if it does not already exist.
    ///
    /// https://developer.mozilla.org/en-US/docs/Web/API/Headers/set
    pub fn set(self: *const Headers, name: []const u8, value: []const u8) void {
        if (self.vtable) |vt| {
            if (self.backend_ctx) |ctx| {
                vt.set(ctx, name, value);
            }
        }
    }

    /// Appends a new value onto an existing header inside a Headers object,
    /// or adds the header if it does not already exist.
    ///
    /// https://developer.mozilla.org/en-US/docs/Web/API/Headers/append
    ///
    /// **Zig Note:** Named `add` instead of `append` in this implementation.
    pub fn add(self: *const Headers, name: []const u8, value: []const u8) void {
        if (self.vtable) |vt| {
            if (self.backend_ctx) |ctx| {
                vt.add(ctx, name, value);
            }
        }
    }
};

// --- Builder (not part of web standard) --- //

/// Builder for creating Response objects.
///
/// **Zig Note:** This is an internal type not present in the web standard.
/// In the web standard, you would use the `new Response(body, init)` constructor.
/// This builder pattern is used for backend implementations to construct
/// Response objects with the appropriate vtable and context.
pub const Builder = struct {
    status: u16 = 200,
    redirected: bool = false,
    url: []const u8 = "",
    response_type: ResponseType = .default,
    arena: std.mem.Allocator,
    backend_ctx: ?*anyopaque = null,
    vtable: ?*const VTable = null,
    headers_ctx: ?*anyopaque = null,
    headers_vtable: ?*const Headers.HeadersVTable = null,

    /// Builds the Response object with all configured values.
    pub fn build(self: Builder) Response {
        return .{
            .body = "",
            .bodyUsed = false,
            .ok = self.status >= 200 and self.status <= 299,
            .redirected = self.redirected,
            .status = self.status,
            .statusText = common.statusCodeToText(self.status),
            .type = self.response_type,
            .url = self.url,
            .arena = self.arena,
            .backend_ctx = self.backend_ctx,
            .vtable = self.vtable,
            .headers = .{
                .backend_ctx = self.headers_ctx,
                .vtable = self.headers_vtable,
            },
        };
    }
};
