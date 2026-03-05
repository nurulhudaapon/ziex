const std = @import("std");
pub const BuiltinAttribute = @import("Attribute.zig").Builtin;

pub const PageMethod = enum {
    GET,
    POST,
    PUT,
    DELETE,
    PATCH,
    OPTIONS,
    HEAD,
    CONNECT,
    TRACE,
    ALL,
};
pub const PageOptions = struct {
    pub const StaticParam = struct {
        key: []const u8,
        value: []const u8,
    };

    /// Options for static page generation during `zx export`
    pub const Static = struct {
        params: ?[]const []const StaticParam = null,
        getParams: ?*const fn (std.mem.Allocator) anyerror![]const []const StaticParam = null,
    };

    rendering: ?BuiltinAttribute.Rendering = null,
    caching: BuiltinAttribute.Caching = .none,
    methods: []const PageMethod = &.{.GET},
    static: ?Static = null,
    /// Enable streaming SSR with async components
    streaming: bool = false,
};

pub const LayoutOptions = struct {
    rendering: ?BuiltinAttribute.Rendering = null,
    caching: BuiltinAttribute.Caching = .none,
};
pub const NotFoundOptions = struct {
    rendering: ?BuiltinAttribute.Rendering = null,
    caching: BuiltinAttribute.Caching = .none,
};
pub const ErrorOptions = struct {};
pub const RouteOptions = struct {
    pub const StaticParam = struct {
        key: []const u8,
        value: []const u8,
    };

    pub const Static = struct {
        params: ?[]const []const StaticParam = null,
        getParams: ?*const fn (std.mem.Allocator) anyerror![]const []const StaticParam = null,
    };

    caching: BuiltinAttribute.Caching = .none,
    static: ?Static = null,
};

/// Options for proxy middleware
pub const ProxyOptions = struct {
    /// Whether to continue to the next handler if proxy doesn't handle the request
    pass_through: bool = true,
};
