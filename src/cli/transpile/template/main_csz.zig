export fn main() void {
    client.info();
    client.renderAll();
}

pub fn renderAll() void {
    client.renderAll();
}

pub var client = zx.Client.init(std.heap.wasm_allocator, .{
    .components = &@import("components.zig").components,
});

const std = @import("std");
const zx = @import("zx");
