//! ZLS backing for the ZX language server.
//!
//! When `-Dzls=true` (and the `zls` dependency is present), `create` wraps
//! `zls.Server` and exposes it through `Handler.VTable`.
//!
//! Until ZLS supports the current Zig version, keep `-Dzls=false` (default).
//! To re-enable later:
//! 1. Uncomment / update the `zls` entry in `build.zig.zon`
//! 2. Build with `-Dzls=true`

const std = @import("std");
const build_options = @import("build_options");
const lsp = @import("lsp");
const Handler = @import("../Handler.zig");

pub const enabled = build_options.enable_zls;

pub const CreateOptions = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    transport: *lsp.Transport,
    environ_map: *const std.process.Environ.Map,
    zx_module: ?[]const u8 = null,
};

pub const Backing = struct {
    ptr: *anyopaque,
    vtable: *const Handler.VTable,
};

pub const CreateError = error{
    ZlsUnavailable,
    OutOfMemory,
    Unexpected,
};

/// Create a ZLS-backed vtable. No-ops to `error.ZlsUnavailable` when ZLS is disabled.
pub fn create(options: CreateOptions) CreateError!Backing {
    if (comptime enabled) {
        return @import("Zls/impl.zig").create(options);
    }
    return error.ZlsUnavailable;
}
