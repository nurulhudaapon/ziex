pub const routes = [_]zx.App.Meta.Route{
    .{
        .path = "/",
        .page = @import(".zx/pages/page.zig").Page,
        .layout = @import(".zx/pages/layout.zig").Layout,
        .notfound = @import(".zx/pages/notfound.zig").NotFound,
        .@"error" = @import(".zx/pages/error.zig").Error,
        .page_opts = getOptions(@import(".zx/pages/page.zig"), zx.PageOptions),
        .layout_opts = getOptions(@import(".zx/pages/layout.zig"), zx.LayoutOptions),
        .notfound_opts = getOptions(@import(".zx/pages/notfound.zig"), zx.NotFoundOptions),
        .error_opts = getOptions(@import(".zx/pages/error.zig"), zx.ErrorOptions),
    },
    .{
        .path = "/learn",
        .page = @import(".zx/pages/learn/page.zig").Page,
        .layout = @import(".zx/pages/learn/layout.zig").Layout,
        .@"error" = @import(".zx/pages/learn/error.zig").Error,
        .page_opts = getOptions(@import(".zx/pages/learn/page.zig"), zx.PageOptions),
        .layout_opts = getOptions(@import(".zx/pages/learn/layout.zig"), zx.LayoutOptions),
        .error_opts = getOptions(@import(".zx/pages/learn/error.zig"), zx.ErrorOptions),
    },
    .{
        .path = "/about",
        .page = @import(".zx/pages/about/page.zig").Page,
        .page_opts = getOptions(@import(".zx/pages/about/page.zig"), zx.PageOptions),
    },
    .{
        .path = "/docs",
        .page = @import(".zx/pages/docs/page.zig").Page,
        .layout = @import(".zx/pages/docs/layout.zig").Layout,
        .page_opts = getOptions(@import(".zx/pages/docs/page.zig"), zx.PageOptions),
        .layout_opts = getOptions(@import(".zx/pages/docs/layout.zig"), zx.LayoutOptions),
    },
    .{
        .path = "/time",
        .page = @import(".zx/pages/time/page.zig").Page,
        .page_opts = getOptions(@import(".zx/pages/time/page.zig"), zx.PageOptions),
    },
    .{
        .path = "/examples",
        .page = @import(".zx/pages/examples/page.zig").Page,
        .layout = @import(".zx/pages/examples/layout.zig").Layout,
        .page_opts = getOptions(@import(".zx/pages/examples/page.zig"), zx.PageOptions),
        .layout_opts = getOptions(@import(".zx/pages/examples/layout.zig"), zx.LayoutOptions),
    },
    .{
        .path = "/examples/form",
        .page = @import(".zx/pages/examples/form/page.zig").Page,
        .page_opts = getOptions(@import(".zx/pages/examples/form/page.zig"), zx.PageOptions),
    },
    .{
        .path = "/examples/wasm",
        .page = @import(".zx/pages/examples/wasm/page.zig").Page,
        .page_opts = getOptions(@import(".zx/pages/examples/wasm/page.zig"), zx.PageOptions),
    },
    .{
        .path = "/examples/wasm/simple",
        .page = @import(".zx/pages/examples/wasm/simple/page.zig").Page,
        .page_opts = getOptions(@import(".zx/pages/examples/wasm/simple/page.zig"), zx.PageOptions),
    },
    .{
        .path = "/examples/overview",
        .page = @import(".zx/pages/examples/overview/page.zig").Page,
        .page_opts = getOptions(@import(".zx/pages/examples/overview/page.zig"), zx.PageOptions),
    },
};

pub const meta = zx.App.Meta{
    .routes = &routes,
    .rootdir = "site/.zx",
};

const zx = @import("zx");

fn getOptions(comptime T: type, comptime R: type) ?R {
    return if (@hasDecl(T, "options")) T.options else null;
}
