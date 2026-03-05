const std = @import("std");

const BuiltinAttribute = @This();

pub const Rendering = enum {
    /// Client-side React.js
    react,
    /// Client-side Zig
    client,
    /// Server-side rendering (default)
    server,
    /// Static rendering (pre-render the component/page/layout as static HTML and store in cache/cdn)
    static,

    pub fn from(value: []const u8) Rendering {
        const v = if (std.mem.startsWith(u8, value, ".")) value[1..value.len] else value;
        return std.meta.stringToEnum(Rendering, v) orelse .client;
    }
};

pub const Escaping = enum {
    /// HTML escaping (default behavior)
    html,
    /// No escaping; outputs raw HTML. Use with caution for trusted content only.
    none, // no escaping
};

pub const Async = enum {
    /// Render synchronously (default)
    sync,
    /// Render asynchronously, stream when ready with inline script replacement
    stream,
};

pub const Caching = struct {
    pub const none = Caching{ .seconds = 0 };

    /// The number of seconds to cache the page for
    seconds: u32,
    /// The key to cache the page for
    key: ?[]const u8 = null,

    /// Examples:
    ///
    /// - `10s` → `{ .seconds = 10, .key = null }`
    /// - `5m` → `{ .seconds = 300, .key = null }`
    /// - `1h` → `{ .seconds = 3600, .key = null }`
    /// - `1d` → `{ .seconds = 86400, .key = null }`
    ///
    /// With key:
    /// - `10s:key` → `{ .seconds = 10, .key = "key" }`
    /// - `5m:key` → `{ .seconds = 300, .key = "key" }`
    /// - `1h:key` → `{ .seconds = 3600, .key = "key" }`
    /// - `1d:key` → `{ .seconds = 86400, .key = "key" }`
    pub fn tag(comptime tag_str: []const u8) Caching {
        comptime {
            var num_end: usize = 0;
            while (num_end < tag_str.len) : (num_end += 1) {
                const c = tag_str[num_end];
                if (!std.ascii.isDigit(c)) break;
            }
            if (num_end == 0) @compileError("Invalid caching tag '" ++ tag_str ++ "': no number found");

            const num_str = tag_str[0..num_end];
            const rest = tag_str[num_end..];

            var unit_end: usize = 0;
            var key: ?[]const u8 = null;
            for (rest, 0..) |c, i| {
                if (c == ':') {
                    unit_end = i;
                    key = rest[i + 1 ..];
                    break;
                }
            } else {
                unit_end = rest.len;
            }
            const unit_str = rest[0..unit_end];

            const num_value = std.fmt.parseInt(u64, num_str, 10) catch @compileError("Invalid caching number '" ++ num_str ++ "'");
            const unit_value = parseUnit(unit_str);

            const seconds = num_value * unit_value;

            return .{ .seconds = seconds, .key = key };
        }
    }

    fn parseUnit(comptime unit: []const u8) comptime_int {
        if (std.mem.eql(u8, unit, "s") or unit.len == 0) return 1;
        if (std.mem.eql(u8, unit, "m")) return std.time.s_per_min;
        if (std.mem.eql(u8, unit, "h")) return std.time.s_per_hour;
        if (std.mem.eql(u8, unit, "d")) return std.time.s_per_day;
        @compileError("Invalid caching unit '" ++ unit ++ "', supported units: s, m, h, d");
    }
};
