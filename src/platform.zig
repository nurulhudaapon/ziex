const builtin = @import("builtin");

pub const Os = enum {
    freestanding,
    wasi,
    linux,
    macos,
    windows,
    ios,
    android,
    other,
};

pub const Role = enum {
    /// Server environment (native binary or WASI edge runtime)
    server,
    /// Client environment (browser WASM or future native mobile/desktop)
    client,
};

pub const Platform = struct {
    os: Os,
    role: Role,

    pub inline fn isClient(self: Platform) bool {
        return self.role == .client;
    }

    pub inline fn isServer(self: Platform) bool {
        return self.role == .server;
    }

    pub inline fn isWasm(self: Platform) bool {
        return self.os == .freestanding or self.os == .wasi;
    }

    pub inline fn isEdge(self: Platform) bool {
        return self.os == .wasi and self.role == .server;
    }
};

/// The platform the code is running on, determined at comptime from the build target.
pub const platform: Platform = .{
    .os = switch (builtin.os.tag) {
        .freestanding => .freestanding,
        .wasi => .wasi,
        .linux => .linux,
        .macos => .macos,
        .windows => .windows,
        .ios => .ios,
        else => .other,
    },
    .role = switch (builtin.os.tag) {
        .freestanding => .client,
        else => .server,
    },
};
