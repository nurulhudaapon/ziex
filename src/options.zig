const std = @import("std");

const pltfm = @import("platform.zig");
const platform = pltfm.platform;
const Client = @import("runtime/client/Client.zig");
const Edge = @import("runtime/server/wasm/entrypoint.zig");

pub const BuiltinAttribute = @import("attributes.zig").builtin;

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
    pub const Method = PageMethod;
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

/// Default std_options for zx apps.
/// Re-export this in your main.zig:
/// ```zig
/// pub const std_options = zx.std_options;
/// ```
pub const std_options: std.Options = .{
    .logFn = switch (platform) {
        .browser => Client.logFn,
        .edge => Edge.logFn,
        else => std.log.defaultLog,
    },
};
