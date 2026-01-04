pub const components = [_]zx.Client.ComponentMeta{
 .{
    .type = .client,
    .id = "zx-2676a2f99c98f8f91dd890d002af04ba-0",
    .name = "CounterComponent",
    .path = "component/csr_zig.zig",
    .import = @import("component/csr_zig.zig").CounterComponent,
    .route = "",
}, .{
    .type = .client,
    .id = "zx-c6f40e3ab2f0caeebf36ba66712cc7fe-1",
    .name = "Button",
    .path = "component/csr_zig.zig",
    .import = @import("component/csr_zig.zig").Button,
    .route = "",
} };

const zx = @import("zx");
