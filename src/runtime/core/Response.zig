const std = @import("std");
const common = @import("common.zig");

pub const Response = @This();

pub const Cookies = common.Cookies;
pub const CookieOptions = common.CookieOptions;
pub const ContentType = common.ContentType;
pub const HttpStatus = common.HttpStatus;

/// The type of the response.
///
/// **Values:**
/// - `basic`: Normal, same origin response, with all headers exposed except "Set-Cookie".
/// - `cors`: Response was received from a valid cross-origin request.
/// - `default`: Default response type (used when response type is not explicitly set).
/// - `error`: Network error. No useful information describing the error is available.
/// - `opaque`: Response for "no-cors" request to cross-origin resource.
/// - `opaqueredirect`: The fetch request was made with redirect: "manual".
///
/// MDN: [Response.type](https://developer.mozilla.org/en-US/docs/Web/API/Response/type)
pub const ResponseType = enum {
    basic,
    cors,
    default,
    @"error",
    @"opaque",
    opaqueredirect,
};

// --- Instance Properties --- //
// MDN: [Response instance properties](https://developer.mozilla.org/en-US/docs/Web/API/Response#instance_properties)

/// A ReadableStream of the body contents.
///
/// MDN: [Response.body](https://developer.mozilla.org/en-US/docs/Web/API/Response/body)
body: []const u8 = "",

/// Stores a boolean value that declares whether the body has been used in a response yet.
///
/// MDN: [Response.bodyUsed](https://developer.mozilla.org/en-US/docs/Web/API/Response/bodyUsed)
bodyUsed: bool = false,

/// The Headers object associated with the response.
///
/// MDN: [Response.headers](https://developer.mozilla.org/en-US/docs/Web/API/Response/headers)
headers: Headers = .{},

/// Cookie accessor for setting/deleting cookies.
cookies: ResponseCookies = .{},

/// A boolean indicating whether the response was successful (status in the range 200–299) or not.
///
/// MDN: [Response.ok](https://developer.mozilla.org/en-US/docs/Web/API/Response/ok)
ok: bool = true,

/// Indicates whether or not the response is the result of a redirect
/// (that is, its URL list has more than one entry).
///
/// MDN: [Response.redirected](https://developer.mozilla.org/en-US/docs/Web/API/Response/redirected)
redirected: bool = false,

/// The status code of the response (e.g., 200 for a success).
///
/// MDN: [Response.status](https://developer.mozilla.org/en-US/docs/Web/API/Response/status)
status: u16 = 200,

/// The status message corresponding to the status code (e.g., "OK" for 200).
///
/// MDN: [Response.statusText](https://developer.mozilla.org/en-US/docs/Web/API/Response/statusText)
statusText: []const u8 = "OK",

/// The type of the response (e.g., basic, cors).
///
/// MDN: [Response.type](https://developer.mozilla.org/en-US/docs/Web/API/Response/type)
type: ResponseType = .default,

/// The URL of the response.
///
/// MDN: [Response.url](https://developer.mozilla.org/en-US/docs/Web/API/Response/url)
url: []const u8 = "",

/// Arena allocator for response-scoped allocations.
arena: std.mem.Allocator,

_internal: Internal = .{},

const Internal = struct {
    userdata: ?*anyopaque = null,
    vtable: ?*const VTable = null,
};

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
pub fn setStatus(self: *const Response, stat: HttpStatus) void {
    if (self._internal.vtable) |vt| {
        if (self._internal.userdata) |ctx| {
            vt.setStatus(ctx, @intFromEnum(stat));
        }
    }
}

/// Sets the response body directly.
pub fn text(self: *const Response, content: []const u8) void {
    if (self._internal.vtable) |vt| {
        if (self._internal.userdata) |ctx| {
            vt.setBody(ctx, content);
        }
    }
}

/// Sets the response body to a JSON string.
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
/// MDN: [Response.headers](https://developer.mozilla.org/en-US/docs/Web/API/Response/headers)
pub fn setHeader(self: *const Response, name: []const u8, value: []const u8) void {
    if (self._internal.vtable) |vt| {
        if (self._internal.userdata) |ctx| {
            vt.setHeader(ctx, name, value);
        }
    }
}

/// Sets the Content-Type header.
pub fn setContentType(self: *const Response, content_type: ContentType) void {
    self.setHeader("Content-Type", content_type.toString());
}

/// Creates a redirect response by setting the Location header and status code.
///
/// **Parameters:**
/// - `location`: The URL to redirect to.
/// - `redirect_status`: Optional status code (default: 302 Found).
///
/// MDN: [Response.redirect()](https://developer.mozilla.org/en-US/docs/Web/API/Response/redirect_static)
pub fn redirect(self: *const Response, location: []const u8, redirect_status: ?u16) void {
    const code = redirect_status orelse 302;
    self.setStatus(@enumFromInt(code));
    self.setHeader("Location", location);
}

/// Gets the response writer for streaming content.
pub fn writer(self: *const Response) ?*std.Io.Writer {
    if (self._internal.vtable) |vt| {
        if (self._internal.userdata) |ctx| {
            return vt.getWriter(ctx);
        }
    }
    return null;
}

/// Writes a chunk for chunked transfer encoding.
pub fn chunk(self: *const Response, data: []const u8) !void {
    if (self._internal.vtable) |vt| {
        if (self._internal.userdata) |ctx| {
            try vt.writeChunk(ctx, data);
        }
    }
}

/// Clears the response writer/buffer.
pub fn clearWriter(self: *const Response) void {
    if (self._internal.vtable) |vt| {
        if (self._internal.userdata) |ctx| {
            vt.clearWriter(ctx);
        }
    }
}

// --- Headers --- //
// MDN: [Headers](https://developer.mozilla.org/en-US/docs/Web/API/Headers)

/// The Headers interface of the Fetch API allows you to perform various actions on HTTP request and response headers.
///
/// MDN: [Headers](https://developer.mozilla.org/en-US/docs/Web/API/Headers)
pub const Headers = struct {
    _internal: State = .{},

    const State = struct {
        userdata: ?*anyopaque = null,
        vtable: ?*const HeadersVTable = null,
    };

    pub const HeadersVTable = struct {
        get: *const fn (ctx: *anyopaque, name: []const u8) ?[]const u8,
        set: *const fn (ctx: *anyopaque, name: []const u8, value: []const u8) void,
        add: *const fn (ctx: *anyopaque, name: []const u8, value: []const u8) void,
    };

    /// Returns the values of a header with the given name.
    ///
    /// MDN: [Headers.get](https://developer.mozilla.org/en-US/docs/Web/API/Headers/get)
    pub fn get(self: *const Headers, name: []const u8) ?[]const u8 {
        if (self._internal.vtable) |vt| {
            if (self._internal.userdata) |ctx| {
                return vt.get(ctx, name);
            }
        }
        return null;
    }

    /// Sets a new value for an existing header inside a Headers object,
    /// or adds the header if it does not already exist.
    ///
    /// MDN: [Headers.set](https://developer.mozilla.org/en-US/docs/Web/API/Headers/set)
    pub fn set(self: *const Headers, name: []const u8, value: []const u8) void {
        if (self._internal.vtable) |vt| {
            if (self._internal.userdata) |ctx| {
                vt.set(ctx, name, value);
            }
        }
    }

    /// Appends a new value onto an existing header inside a Headers object,
    /// or adds the header if it does not already exist.
    ///
    /// MDN: [Headers.append](https://developer.mozilla.org/en-US/docs/Web/API/Headers/append)
    pub fn add(self: *const Headers, name: []const u8, value: []const u8) void {
        if (self._internal.vtable) |vt| {
            if (self._internal.userdata) |ctx| {
                vt.add(ctx, name, value);
            }
        }
    }
};

// --- Cookies --- //

/// The ResponseCookies interface provides utility methods to work with cookies on the response.
pub const ResponseCookies = struct {
    _internal: State = .{},

    const State = struct {
        userdata: ?*anyopaque = null,
        vtable: ?*const VTable = null,
    };

    /// Sets a cookie on the response.
    ///
    /// MDN: [Cookies](https://developer.mozilla.org/en-US/docs/Web/HTTP/Cookies)
    pub fn set(self: *const ResponseCookies, name: []const u8, value: []const u8, options: ?CookieOptions) void {
        const opts = options orelse CookieOptions{};
        if (self._internal.vtable) |vt| {
            if (self._internal.userdata) |ctx| {
                vt.setCookie(ctx, name, value, opts) catch {};
            }
        }
    }

    /// Deletes a cookie by setting it with an expired max-age.
    pub fn delete(self: *const ResponseCookies, name: []const u8, options: ?CookieOptions) void {
        var opts = options orelse CookieOptions{};
        opts.max_age = 0;
        self.set(name, "", opts);
    }
};

/// Builder for creating Response objects.
pub const Builder = struct {
    status: u16 = 200,
    redirected: bool = false,
    url: []const u8 = "",
    response_type: ResponseType = .default,
    arena: std.mem.Allocator,
    userdata: ?*anyopaque = null,
    vtable: ?*const VTable = null,
    headers_userdata: ?*anyopaque = null,
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
            ._internal = .{
                .userdata = self.userdata,
                .vtable = self.vtable,
            },
            .arena = self.arena,
            .headers = .{
                ._internal = .{
                    .userdata = self.headers_userdata,
                    .vtable = self.headers_vtable,
                },
            },
            .cookies = .{
                ._internal = .{
                    .userdata = self.userdata,
                    .vtable = self.vtable,
                },
            },
        };
    }
};
