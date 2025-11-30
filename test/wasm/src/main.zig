pub const components = [_]zx.BOM.ComponentMetadata{
    .{
        .type = .csz,
        .id = "zx-3badae80b344e955a3048888ed2aae42",
        .name = "CounterComponent",
        .path = "component/csr_zig.zig",
        .import = @import("component.zig").CounterComponent,
    },
};

export fn main() void {
    const allocator = std.heap.wasm_allocator;

    for (components) |component| {
        zx.BOM.renderToContainer(allocator, component) catch unreachable;
    }
}

export var count: i32 = 0;

export fn onclick(value: i32) void {
    const allocator = std.heap.wasm_allocator;

    const console = Console.init();
    defer console.deinit();

    count += 1;

    const event = Event.idxInit(allocator, value) catch @panic("Failed to get event");

    console.log(.{
        js.string("Value: "),
        value,
        js.string("Count: "),
        event._count,
        js.string("Data: "),
        js.string(event.target.value),
    });

    main();
}

const std = @import("std");
const zx = @import("zx");
const js = @import("js");

const BOM = @import("zx").BOM;
const Console = BOM.Console;
const Document = BOM.Document;
const Event = BOM.Event;
