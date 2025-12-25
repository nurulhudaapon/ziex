pub const routes = [_]zx.App.Meta.Route{
    .{
        .path = "/",
        .page = @import(".zx/pages/page.zig").Page,
        .layout = @import(".zx/pages/layout.zig").Layout,
        .options = if (@hasDecl(@import(".zx/pages/page.zig"), "options")) @import(".zx/pages/page.zig").options else null,
    },
    .{
        .path = "/about",
        .page = @import(".zx/pages/about/page.zig").Page,
    },
    .{
        .path = "/docs",
        .page = @import(".zx/pages/docs/page.zig").Page,
        .layout = @import(".zx/pages/docs/layout.zig").Layout,
    },
    .{
        .path = "/learn",
        .page = @import(".zx/pages/learn/page.zig").Page,
    },
    .{
        .path = "/examples",
        .page = @import(".zx/pages/examples/page.zig").Page,
    },
    .{
        .path = "/examples/form",
        .page = @import(".zx/pages/examples/form/page.zig").Page,
    },
    .{
        .path = "/cli",
        .page = @import(".zx/pages/cli/page.zig").Page,
        .layout = @import(".zx/pages/cli/layout.zig").Layout,
    },
    .{
        .path = "/time",
        .page = @import(".zx/pages/time/page.zig").Page,
        .options = if (@hasDecl(@import(".zx/pages/time/page.zig"), "options")) @import(".zx/pages/time/page.zig").options else null,
    },
    .{
        .path = "/examples/wasm",
        .page = @import(".zx/pages/examples/wasm/page.zig").Page,
    },
    .{
        .path = "/examples/wasm/simple",
        .page = @import(".zx/pages/examples/wasm/simple/page.zig").Page,
    },
    .{
        .path = "/examples/overview",
        .page = @import(".zx/pages/examples/overview/page.zig").Page,
    },
};

pub const meta = zx.App.Meta{
    .routes = &routes,
    .rootdir = "site/.zx",
};

const zx = @import("zx");
