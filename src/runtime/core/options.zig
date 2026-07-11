const std = @import("std");

const pltfm = @import("../../platform.zig");
const platform = pltfm.platform;
const Client = @import("../client/Client.zig");
const Edge = @import("App/Wasm.zig");

pub const BuiltinAttribute = @import("../../attributes.zig").builtin;

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

pub const StaticParam = struct {
    key: []const u8,
    value: []const u8,
};

pub const StaticParams = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList([]const StaticParam) = .empty,

    /// Add one parameter combination to pre-render. Pass an anonymous struct
    /// whose fields name the dynamic segments:
    /// ```zig
    /// try ctx.params.add(.{ .slug = "hello-world" });
    /// try ctx.params.add(.{ .category = "zig", .slug = "intro" });
    /// ```
    pub fn add(self: *StaticParams, params: anytype) !void {
        const T = @TypeOf(params);
        const field_names = @typeInfo(T).@"struct".field_names;
        const set = try self.allocator.alloc(StaticParam, field_names.len);
        inline for (field_names, 0..) |field_name, i| {
            set[i] = .{ .key = field_name, .value = @field(params, field_name) };
        }
        try self.entries.append(self.allocator, set);
    }

    /// Add a raw key/value parameter set. Use this when segment names are not
    /// known at comptime; otherwise prefer `add`.
    pub fn addRaw(self: *StaticParams, set: []const StaticParam) !void {
        try self.entries.append(self.allocator, set);
    }
};

/// Context passed to a page or route's `static` function during `zx export`.
/// Use `ctx.params.add(...)` to declare which dynamic parameter combinations
/// should be pre-rendered to static HTML.
///
/// ```zig
/// pub const options = zx.PageOptions{
///     .static = staticParams,
/// };
///
/// fn staticParams(ctx: *zx.StaticContext) !void {
///     try ctx.params.add(.{ .slug = "hello-world" });
///     try ctx.params.add(.{ .slug = "intro" });
/// }
/// ```
pub const StaticContext = struct {
    arena: std.mem.Allocator,
    params: StaticParams,

    pub fn init(arena: std.mem.Allocator) StaticContext {
        return .{ .arena = arena, .params = .{ .allocator = arena } };
    }
};

/// A `static` function: receives a `StaticContext` and declares the dynamic
/// parameter combinations to pre-render via `ctx.params.add(...)`.
pub const StaticFn = *const fn (ctx: *StaticContext) anyerror!void;

pub const PageOptions = struct {
    pub const Method = PageMethod;

    rendering: ?BuiltinAttribute.Rendering = null,
    caching: ?BuiltinAttribute.Caching = null,
    methods: []const PageMethod = &.{.GET},
    static: ?StaticFn = null,
    /// Enable streaming SSR with async components
    streaming: bool = false,
};

pub const LayoutOptions = struct {
    rendering: ?BuiltinAttribute.Rendering = null,
    caching: ?BuiltinAttribute.Caching = null,
};
pub const NotFoundOptions = struct {
    rendering: ?BuiltinAttribute.Rendering = null,
    caching: ?BuiltinAttribute.Caching = null,
};
pub const ErrorOptions = struct {};
pub const RouteOptions = struct {
    caching: ?BuiltinAttribute.Caching = null,
    static: ?StaticFn = null,
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
    .logFn = switch (platform.os) {
        .freestanding => Client.logFn,
        .wasi => Edge.logFn,
        else => std.log.defaultLog,
    },
    .log_scope_levels = &.{
        .{ .scope = .websocket, .level = .warn },
    },
};
