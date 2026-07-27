const std = @import("std");
const builtin = @import("builtin");

fn alloc(size: usize) callconv(.c) ?[*]u8 {
    if (size == 0) return null;
    const ptr = std.heap.wasm_allocator.alloc(u8, size) catch return null;
    return ptr.ptr;
}

fn free(ptr: [*]u8, size: usize) callconv(.c) void {
    if (size == 0) return;
    std.heap.wasm_allocator.free(ptr[0..size]);
}

comptime {
    if (builtin.cpu.arch.isWasm()) {
        @export(&alloc, .{ .name = "__zx_alloc" });
        @export(&free, .{ .name = "__zx_free" });
    }
}

comptime {
    _ = @import("host.zig");
}
