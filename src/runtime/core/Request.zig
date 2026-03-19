//! The Request interface of the Fetch API represents a resource request.
//!
//! You can create a new Request object using the Request.Builder, but you are more likely
//! to encounter a Request object being returned as part of another API operation, such as
//! a page handler context receiving an incoming HTTP request.
//!
//! This module is backend-agnostic. The actual implementation is provided via vtable.
//!
//! https://developer.mozilla.org/en-US/docs/Web/API/Request

const std = @import("std");
const common = @import("common.zig");
const FormDataModule = @import("FormData.zig");
const MultiFormDataModule = @import("MultiFormData.zig");

pub const Request = @This();

pub const FormData = FormDataModule;
pub const MultiFormData = MultiFormDataModule;
pub const Method = common.Method;
pub const Version = common.Version;
pub const Cookies = common.Cookies;
pub const Header = common.Header;
pub const MultiFormEntry = common.MultiFormEntry;

// --- Instance Properties --- //
// https://developer.mozilla.org/en-US/docs/Web/API/Request#instance_properties

/// Contains the URL of the request.
///
/// https://developer.mozilla.org/en-US/docs/Web/API/Request/url
url: []const u8,

/// Contains the request's method (GET, POST, etc.).
///
/// https://developer.mozilla.org/en-US/docs/Web/API/Request/method
///
/// **Zig Note:** In the web standard, this is a string. In this implementation,
/// it is represented as a `Method` enum for type safety. The original string
/// is available via `method_str`.
method: Method,

/// Contains the request's method as a string.
///
/// **Zig Note:** This is an extension field. In the web standard, `method` is
/// already a string. This field preserves the original string representation.
method_str: []const u8 = "",

/// Contains the pathname portion of the URL.
///
/// **Zig Note:** This is an extension field not present in the web standard Request.
/// In the web standard, you would parse the URL to get the pathname.
/// Example: https://foo.com/bar/baz -> /bar/baz
pathname: []const u8,

/// Contains the referrer of the request (e.g., client, no-referrer, or a URL).
///
/// https://developer.mozilla.org/en-US/docs/Web/API/Request/referrer
///
/// **Zig Note:** In the web standard, this defaults to "about:client". In this
/// implementation, it defaults to an empty string.
referrer: []const u8 = "",

/// Contains the search/query string portion of the URL.
///
/// **Zig Note:** This is an extension field not present in the web standard Request.
/// In the web standard, you would parse the URL to get the search string.
/// Example: https://foo.com/bar?q=qux -> q=qux
search: []const u8 = "",

/// Contains the associated Headers object of the request.
///
/// https://developer.mozilla.org/en-US/docs/Web/API/Request/headers
headers: Headers,

/// Cookie accessor for parsing cookies from the Cookie header.
///
/// **Zig Note:** This is an extension field not present in the web standard Request.
/// In the web standard, you would access cookies via `document.cookie` or parse
/// the Cookie header manually.
cookies: Cookies = .{ .header_value = "" },

/// URL search parameters accessor.
///
/// **Zig Note:** This is an extension field. In the web standard, you would use
/// `new URL(request.url).searchParams` to access search parameters.
///
/// https://developer.mozilla.org/en-US/docs/Web/API/URLSearchParams
searchParams: URLSearchParams = .{},
formdata_backend_ctx: ?*anyopaque = null,
formdata_vtable: ?*const FormDataVTable = null,
multiformdata_backend_ctx: ?*anyopaque = null,
multiformdata_vtable: ?*const MultiFormDataVTable = null,

/// HTTP protocol version (HTTP/1.0 or HTTP/1.1).
///
/// **Zig Note:** This is an extension field not present in the web standard Request.
/// The web standard Request doesn't expose the HTTP protocol version.
/// Uses `std.http.Version` from the standard library.
protocol: Version = .@"HTTP/1.1",

// --- Internal Fields (not part of web standard) --- //

/// Arena allocator for request-scoped allocations.
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
/// Allows different HTTP server backends to implement request operations.
vtable: ?*const VTable = null,

/// VTable interface for backend-specific request operations.
///
/// **Zig Note:** This is an internal type not present in the web standard.
pub const VTable = struct {
    /// Returns the request body as text.
    text: *const fn (ctx: *anyopaque) ?[]const u8 = &defaultText,
    /// Returns a URL parameter by name (from route matching).
    getParam: *const fn (ctx: *anyopaque, name: []const u8) ?[]const u8 = &defaultGetParam,

    fn defaultText(_: *anyopaque) ?[]const u8 {
        return null;
    }
    fn defaultGetParam(_: *anyopaque, _: []const u8) ?[]const u8 {
        return null;
    }
};

// --- Instance Methods --- //
// https://developer.mozilla.org/en-US/docs/Web/API/Request#instance_methods

/// Returns a promise that resolves with a text representation of the request body.
///
/// https://developer.mozilla.org/en-US/docs/Web/API/Request/text
///
/// **Zig Note:** In the web standard, this returns a Promise<string>. In this
/// implementation, it returns `?[]const u8` synchronously (null if no body).
pub fn text(self: *const Request) ?[]const u8 {
    if (self.vtable) |vt| {
        if (self.backend_ctx) |ctx| {
            return vt.text(ctx);
        }
    }
    return null;
}

pub fn json(self: *const Request, comptime T: type, opts: std.json.ParseOptions) !?T {
    const raw = self.text() orelse return null;
    const parsed = std.json.parseFromSlice(T, self.arena, raw, opts) catch return null;
    return parsed.value;
}

/// Returns a URL parameter by name (from route matching).
///
/// **Zig Note:** This is an extension method not present in the web standard Request.
/// Used for accessing dynamic route parameters (e.g., /users/:id -> getParam("id")).
pub fn getParam(self: *const Request, name: []const u8) ?[]const u8 {
    if (self.vtable) |vt| {
        if (self.backend_ctx) |ctx| {
            return vt.getParam(ctx, name);
        }
    }
    return null;
}

/// Returns a typed URL parameter by name (from route matching).
///
/// **Zig Note:** This is an extension method not present in the web standard Request.
/// Used for accessing dynamic route parameters (e.g., /users/:id -> getParam("id")).
pub fn getParamAs(self: *const Request, name: []const u8, comptime T: type) ?T {
    const str = self.getParam(name) orelse return null;

    return switch (@typeInfo(T)) {
        .pointer => |p| switch (p.size) {
            .Slice => if (p.child == u8 and p.is_const) str
                      else @compileError("getParamAs: only []const u8 is supported, got " ++ @typeName(T)),
            else => @compileError("getParamAs: only []const u8 is supported, got " ++ @typeName(T)),
        },
        .int   => std.fmt.parseInt(T, str, 10) catch return null,
        .float => std.fmt.parseFloat(T, str) catch return null,
        .bool  => if (std.mem.eql(u8, str, "true")  or std.mem.eql(u8, str, "1")) true
             else if (std.mem.eql(u8, str, "false") or std.mem.eql(u8, str, "0")) false
             else return null,
        .@"enum"  => std.meta.stringToEnum(T, str) orelse return null,
        else => @compileError("getParamAs: unsupported type " ++ @typeName(T)),
    };
}

/// Returns a FormData object representing the URL-encoded form data of the request body.
///
/// https://developer.mozilla.org/en-US/docs/Web/API/Request/formData
///
/// **Zig Note:** In the web standard, this returns a Promise<FormData>. In this
/// implementation, it returns a FormData object synchronously which provides
/// methods to access form fields. For multipart/form-data with file uploads,
/// use `multiFormData()` instead.
pub fn formData(self: *const Request) FormDataModule {
    return (FormDataModule.Builder{
        .backend_ctx = self.formdata_backend_ctx,
        .vtable = self.formdata_vtable,
    }).build();
}

/// Returns a MultiFormData object representing the multipart form data of the request body.
///
/// **Zig Note:** This is an extension method for handling multipart/form-data with file uploads.
/// For simple key-value form data (application/x-www-form-urlencoded), use `formData()` instead.
pub fn multiFormData(self: *const Request) MultiFormDataModule {
    return (MultiFormDataModule.Builder{
        .backend_ctx = self.multiformdata_backend_ctx,
        .vtable = self.multiformdata_vtable,
    }).build();
}

pub const FormDataVTable = FormDataModule.VTable;
pub const MultiFormDataVTable = MultiFormDataModule.VTable;

// --- URLSearchParams --- //
// https://developer.mozilla.org/en-US/docs/Web/API/URLSearchParams

/// The URLSearchParams interface defines utility methods to work with the
/// query string of a URL.
///
/// https://developer.mozilla.org/en-US/docs/Web/API/URLSearchParams
///
/// **Zig Note:** This is a simplified implementation that delegates to the backend.
/// Not all methods from the web standard URLSearchParams interface are implemented.
pub const URLSearchParams = struct {
    backend_ctx: ?*anyopaque = null,
    vtable: ?*const URLSearchParamsVTable = null,

    pub const URLSearchParamsVTable = struct {
        get: *const fn (ctx: *anyopaque, name: []const u8) ?[]const u8,
        has: *const fn (ctx: *anyopaque, name: []const u8) bool,
    };

    /// Returns the first value associated with the given search parameter.
    ///
    /// https://developer.mozilla.org/en-US/docs/Web/API/URLSearchParams/get
    ///
    /// **Zig Note:** Returns `?[]const u8` instead of `string | null`.
    pub fn get(self: *const URLSearchParams, name: []const u8) ?[]const u8 {
        if (self.vtable) |vt| {
            if (self.backend_ctx) |ctx| {
                return vt.get(ctx, name);
            }
        }
        return null;
    }

    /// Returns a boolean indicating if such a given parameter exists.
    ///
    /// https://developer.mozilla.org/en-US/docs/Web/API/URLSearchParams/has
    pub fn has(self: *const URLSearchParams, name: []const u8) bool {
        if (self.vtable) |vt| {
            if (self.backend_ctx) |ctx| {
                return vt.has(ctx, name);
            }
        }
        return false;
    }
};

// --- Headers --- //
// https://developer.mozilla.org/en-US/docs/Web/API/Headers

/// The Headers interface of the Fetch API allows you to perform various actions
/// on HTTP request and response headers.
///
/// https://developer.mozilla.org/en-US/docs/Web/API/Headers
///
/// **Zig Note:** This is a simplified read-only implementation for request headers.
/// Not all methods from the web standard Headers interface are implemented.
pub const Headers = struct {
    backend_ctx: ?*anyopaque = null,
    vtable: ?*const HeadersVTable = null,

    pub const HeadersVTable = struct {
        get: *const fn (ctx: *anyopaque, name: []const u8) ?[]const u8,
        has: *const fn (ctx: *anyopaque, name: []const u8) bool,
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

    /// Returns a boolean stating whether a Headers object contains a certain header.
    ///
    /// https://developer.mozilla.org/en-US/docs/Web/API/Headers/has
    pub fn has(self: *const Headers, name: []const u8) bool {
        if (self.vtable) |vt| {
            if (self.backend_ctx) |ctx| {
                return vt.has(ctx, name);
            }
        }
        return false;
    }
};

// --- Builder (not part of web standard) --- //

/// Builder for creating Request objects.
///
/// **Zig Note:** This is an internal type not present in the web standard.
/// In the web standard, you would use the `new Request(input, init)` constructor.
/// This builder pattern is used for backend implementations to construct
/// Request objects with the appropriate vtable and context.
pub const Builder = struct {
    url: []const u8 = "",
    method: Method = .GET,
    method_str: []const u8 = "GET",
    pathname: []const u8 = "/",
    referrer: []const u8 = "",
    search: []const u8 = "",
    protocol: Version = .@"HTTP/1.1",
    arena: std.mem.Allocator,
    backend_ctx: ?*anyopaque = null,
    vtable: ?*const VTable = null,
    headers_ctx: ?*anyopaque = null,
    headers_vtable: ?*const Headers.HeadersVTable = null,
    cookie_header: []const u8 = "",
    search_params_ctx: ?*anyopaque = null,
    search_params_vtable: ?*const URLSearchParams.URLSearchParamsVTable = null,
    formdata_ctx: ?*anyopaque = null,
    formdata_vtable: ?*const FormDataVTable = null,
    multiformdata_ctx: ?*anyopaque = null,
    multiformdata_vtable: ?*const MultiFormDataVTable = null,

    /// Builds the Request object with all configured values.
    pub fn build(self: Builder) Request {
        return .{
            .url = self.url,
            .method = self.method,
            .method_str = self.method_str,
            .pathname = self.pathname,
            .referrer = self.referrer,
            .search = self.search,
            .protocol = self.protocol,
            .arena = self.arena,
            .backend_ctx = self.backend_ctx,
            .vtable = self.vtable,
            .headers = .{
                .backend_ctx = self.headers_ctx,
                .vtable = self.headers_vtable,
            },
            .cookies = .{ .header_value = self.cookie_header },
            .searchParams = .{
                .backend_ctx = self.search_params_ctx,
                .vtable = self.search_params_vtable,
            },
            .formdata_backend_ctx = self.formdata_ctx,
            .formdata_vtable = self.formdata_vtable,
            .multiformdata_backend_ctx = self.multiformdata_ctx,
            .multiformdata_vtable = self.multiformdata_vtable,
        };
    }
};
