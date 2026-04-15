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
// MDN: [Request instance properties](https://developer.mozilla.org/en-US/docs/Web/API/Request#instance_properties)

/// Contains the URL of the request.
///
/// MDN: [Request.url](https://developer.mozilla.org/en-US/docs/Web/API/Request/url)
url: []const u8,

/// Contains the request's method (GET, POST, etc.).
///
/// In this implementation, it is represented as a `Method` enum. The original string is available via `method_str`.
///
/// MDN: [Request.method](https://developer.mozilla.org/en-US/docs/Web/API/Request/method)
method: Method,

/// Contains the request's method as a string.
method_str: []const u8 = "",

/// Contains the pathname portion of the URL.
///
/// Contains the pathname portion of the URL.
///
/// MDN: [URL.pathname](https://developer.mozilla.org/en-US/docs/Web/API/URL/pathname)
pathname: []const u8,

/// Contains the referrer of the request (e.g., client, no-referrer, or a URL).
///
/// MDN: [Request.referrer](https://developer.mozilla.org/en-US/docs/Web/API/Request/referrer)
referrer: []const u8 = "",

/// Contains the search/query string portion of the URL.
///
/// MDN: [URL.search](https://developer.mozilla.org/en-US/docs/Web/API/URL/search)
search: []const u8 = "",

/// Contains the associated Headers object of the request.
///
/// MDN: [Request.headers](https://developer.mozilla.org/en-US/docs/Web/API/Request/headers)
headers: Headers,

/// Cookie accessor for parsing cookies from the Cookie header.
///
/// MDN: [Cookies](https://developer.mozilla.org/en-US/docs/Web/HTTP/Cookies)
cookies: Cookies = .{ .header_value = "" },

/// URL search parameters accessor.
///
/// MDN: [URLSearchParams](https://developer.mozilla.org/en-US/docs/Web/API/URLSearchParams)
queries: URLSearchParams = .{},

/// URL parameters accessor from route matching.
params: Params = .{},

/// HTTP protocol version (HTTP/1.0 or HTTP/1.1).
protocol: Version = .@"HTTP/1.1",

/// Arena allocator for request-scoped allocations.
arena: std.mem.Allocator,

_internal: Internal = .{},

const Internal = struct {
    const UserData = struct {
        request: ?*anyopaque = null,
        headers: ?*anyopaque = null,
        search_params: ?*anyopaque = null,
        params: ?*anyopaque = null,
        formdata: ?*anyopaque = null,
        multiformdata: ?*anyopaque = null,
    };

    const VTables = struct {
        request: ?*const VTable = null,
        headers: ?*const Headers.HeadersVTable = null,
        search_params: ?*const URLSearchParams.URLSearchParamsVTable = null,
        params: ?*const Params.ParamsVTable = null,
        formdata: ?*const FormDataVTable = null,
        multiformdata: ?*const MultiFormDataVTable = null,
    };

    userdata: UserData = .{},
    vtable: VTables = .{},
};

/// VTable interface for backend-specific request operations.
pub const VTable = struct {
    /// Returns the request body as text.
    text: *const fn (ctx: *anyopaque) ?[]const u8 = &defaultText,

    fn defaultText(_: *anyopaque) ?[]const u8 {
        return null;
    }
};

// --- Instance Methods --- //
// MDN: [Request instance methods](https://developer.mozilla.org/en-US/docs/Web/API/Request#instance_methods)

/// Returns the request body as text.
///
/// MDN: [Request.text](https://developer.mozilla.org/en-US/docs/Web/API/Request/text)
pub fn text(self: *const Request) ?[]const u8 {
    if (self._internal.vtable.request) |vt| {
        if (self._internal.userdata.request) |ctx| {
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

/// Returns the URL-encoded form data of the request body.
///
/// MDN: [Request.formData](https://developer.mozilla.org/en-US/docs/Web/API/Request/formData)
pub fn formData(self: *const Request) FormDataModule {
    return (FormDataModule.Builder{
        .backend_ctx = self._internal.userdata.formdata,
        .vtable = self._internal.vtable.formdata,
    }).build();
}

/// Returns the multipart form data of the request body.
pub fn multiFormData(self: *const Request) MultiFormDataModule {
    return (MultiFormDataModule.Builder{
        .backend_ctx = self._internal.userdata.multiformdata,
        .vtable = self._internal.vtable.multiformdata,
    }).build();
}

pub const FormDataVTable = FormDataModule.VTable;
pub const MultiFormDataVTable = MultiFormDataModule.VTable;

// --- URLSearchParams --- //
// MDN: [URLSearchParams](https://developer.mozilla.org/en-US/docs/Web/API/URLSearchParams)

/// The URLSearchParams interface defines utility methods to work with the query string of a URL.
///
/// MDN: [URLSearchParams](https://developer.mozilla.org/en-US/docs/Web/API/URLSearchParams)
pub const URLSearchParams = struct {
    _internal: State = .{},

    const State = struct {
        userdata: ?*anyopaque = null,
        vtable: ?*const URLSearchParamsVTable = null,
    };

    pub const URLSearchParamsVTable = struct {
        get: *const fn (ctx: *anyopaque, name: []const u8) ?[]const u8,
        has: *const fn (ctx: *anyopaque, name: []const u8) bool,
    };

    /// Returns the first value associated with the given search parameter.
    /// MDN: [URLSearchParams.get](https://developer.mozilla.org/en-US/docs/Web/API/URLSearchParams/get)
    pub fn get(self: *const URLSearchParams, name: []const u8) ?[]const u8 {
        if (self._internal.vtable) |vt| {
            if (self._internal.userdata) |ctx| {
                return vt.get(ctx, name);
            }
        }
        return null;
    }

    /// Returns a boolean indicating if the given parameter exists.
    ///
    /// MDN: [URLSearchParams.has](https://developer.mozilla.org/en-US/docs/Web/API/URLSearchParams/has)
    pub fn has(self: *const URLSearchParams, name: []const u8) bool {
        if (self._internal.vtable) |vt| {
            if (self._internal.userdata) |ctx| {
                return vt.has(ctx, name);
            }
        }
        return false;
    }
};

// --- Params --- //

/// The Params interface provides utility methods to work with URL parameters.
/// extracted from dynamic routes.
pub const Params = struct {
    _internal: State = .{},

    const State = struct {
        userdata: ?*anyopaque = null,
        vtable: ?*const ParamsVTable = null,
    };

    pub const ParamsVTable = struct {
        getParam: *const fn (ctx: *anyopaque, name: []const u8) ?[]const u8 = &defaultGetParam,

        fn defaultGetParam(_: *anyopaque, _: []const u8) ?[]const u8 {
            return null;
        }
    };

    /// Returns the value of a URL parameter by name.
    pub fn get(self: *const Params, name: []const u8) ?[]const u8 {
        if (self._internal.vtable) |vt| {
            if (self._internal.userdata) |ctx| {
                return vt.getParam(ctx, name);
            }
        }
        return null;
    }

    /// Returns a typed value of a URL parameter by name.
    pub fn as(self: *const Params, name: []const u8, comptime T: type) ?T {
        const str = self.get(name) orelse return null;

        return switch (@typeInfo(T)) {
            .pointer => |p| switch (p.size) {
                .Slice => if (p.child == u8 and p.is_const) str else @compileError("Params.as: only []const u8 is supported, got " ++ @typeName(T)),
                else => @compileError("Params.as: only []const u8 is supported, got " ++ @typeName(T)),
            },
            .int => std.fmt.parseInt(T, str, 10) catch return null,
            .float => std.fmt.parseFloat(T, str) catch return null,
            .bool => if (std.mem.eql(u8, str, "true") or std.mem.eql(u8, str, "1")) true else if (std.mem.eql(u8, str, "false") or std.mem.eql(u8, str, "0")) false else return null,
            .@"enum" => std.meta.stringToEnum(T, str) orelse return null,
            else => @compileError("Params.as: unsupported type " ++ @typeName(T)),
        };
    }
};

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
        has: *const fn (ctx: *anyopaque, name: []const u8) bool,
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

    /// Returns a boolean stating whether a Headers object contains a certain header.
    ///
    /// MDN: [Headers.has](https://developer.mozilla.org/en-US/docs/Web/API/Headers/has)
    pub fn has(self: *const Headers, name: []const u8) bool {
        if (self._internal.vtable) |vt| {
            if (self._internal.userdata) |ctx| {
                return vt.has(ctx, name);
            }
        }
        return false;
    }
};

/// Builder for creating Request objects.
pub const Builder = struct {
    url: []const u8 = "",
    method: Method = .GET,
    method_str: []const u8 = "GET",
    pathname: []const u8 = "/",
    referrer: []const u8 = "",
    search: []const u8 = "",
    protocol: Version = .@"HTTP/1.1",
    arena: std.mem.Allocator,
    userdata: ?*anyopaque = null,
    vtable: ?*const VTable = null,
    headers_userdata: ?*anyopaque = null,
    headers_vtable: ?*const Headers.HeadersVTable = null,
    cookie_header: []const u8 = "",
    search_params_userdata: ?*anyopaque = null,
    search_params_vtable: ?*const URLSearchParams.URLSearchParamsVTable = null,
    params_userdata: ?*anyopaque = null,
    params_vtable: ?*const Params.ParamsVTable = null,
    formdata_userdata: ?*anyopaque = null,
    formdata_vtable: ?*const FormDataVTable = null,
    multiformdata_userdata: ?*anyopaque = null,
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
            ._internal = .{
                .userdata = .{
                    .request = self.userdata,
                    .headers = self.headers_userdata,
                    .search_params = self.search_params_userdata,
                    .params = self.params_userdata,
                    .formdata = self.formdata_userdata,
                    .multiformdata = self.multiformdata_userdata,
                },
                .vtable = .{
                    .request = self.vtable,
                    .headers = self.headers_vtable,
                    .search_params = self.search_params_vtable,
                    .params = self.params_vtable,
                    .formdata = self.formdata_vtable,
                    .multiformdata = self.multiformdata_vtable,
                },
            },
            .headers = .{
                ._internal = .{
                    .userdata = self.headers_userdata,
                    .vtable = self.headers_vtable,
                },
            },
            .cookies = .{ .header_value = self.cookie_header },
            .queries = .{
                ._internal = .{
                    .userdata = self.search_params_userdata,
                    .vtable = self.search_params_vtable,
                },
            },
            .params = .{
                ._internal = .{
                    .userdata = self.params_userdata orelse self.userdata,
                    .vtable = self.params_vtable,
                },
            },
        };
    }
};
