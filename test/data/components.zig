pub const components = [_]zx.Client.ComponentMeta{
.{
    .type = .csz,
    .id = "zx-3badae80b344e955a3048888ed2aae42",
    .name = "CounterComponent",
    .path = "component/csr_zig.zig",
    .import = @import("component/csr_zig.zig").CounterComponent,
    .route = "",
}};

const zx = @import("zx");
