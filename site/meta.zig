pub const routes = [_]zx.App.Meta.Route{
    .{
        .path = "/",
        .page = wrapPage(@import(".zx/pages/page.zig").Page),
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
        .page = wrapPage(@import(".zx/pages/learn/page.zig").Page),
        .layout = @import(".zx/pages/learn/layout.zig").Layout,
        .@"error" = @import(".zx/pages/learn/error.zig").Error,
        .page_opts = getOptions(@import(".zx/pages/learn/page.zig"), zx.PageOptions),
        .layout_opts = getOptions(@import(".zx/pages/learn/layout.zig"), zx.LayoutOptions),
        .error_opts = getOptions(@import(".zx/pages/learn/error.zig"), zx.ErrorOptions),
    },
    .{
        .path = "/about",
        // .page = wrapPage(@import(".zx/pages/about/page.zig").Page),
        // .page_opts = getOptions(@import(".zx/pages/about/page.zig"), zx.PageOptions),
        .route = zx.App.Meta.route(@import(".zx/pages/about/route.zig"), @import(".zx/pages/about/page.zig")),
        .route_opts = getOptions(@import(".zx/pages/about/route.zig"), zx.RouteOptions),
    },
    .{
        .path = "/about/api",
        .route = zx.App.Meta.route(@import(".zx/pages/about/api/route.zig"), null),
        .route_opts = getOptions(@import(".zx/pages/about/api/route.zig"), zx.RouteOptions),
    },
    .{
        .path = "/docs",
        .page = wrapPage(@import(".zx/pages/docs/page.zig").Page),
        .layout = @import(".zx/pages/docs/layout.zig").Layout,
        .page_opts = getOptions(@import(".zx/pages/docs/page.zig"), zx.PageOptions),
        .layout_opts = getOptions(@import(".zx/pages/docs/layout.zig"), zx.LayoutOptions),
    },
    .{
        .path = "/time",
        .page = wrapPage(@import(".zx/pages/time/page.zig").Page),
        .page_opts = getOptions(@import(".zx/pages/time/page.zig"), zx.PageOptions),
    },
    .{
        .path = "/overview",
        .page = wrapPage(@import(".zx/pages/overview/page.zig").Page),
        .page_opts = getOptions(@import(".zx/pages/overview/page.zig"), zx.PageOptions),
    },
    .{
        .path = "/examples",
        .page = wrapPage(@import(".zx/pages/examples/page.zig").Page),
        .layout = @import(".zx/pages/examples/layout.zig").Layout,
        .page_opts = getOptions(@import(".zx/pages/examples/page.zig"), zx.PageOptions),
        .layout_opts = getOptions(@import(".zx/pages/examples/layout.zig"), zx.LayoutOptions),
    },
    .{
        .path = "/examples/form",
        .page = wrapPage(@import(".zx/pages/examples/form/page.zig").Page),
        .page_opts = getOptions(@import(".zx/pages/examples/form/page.zig"), zx.PageOptions),
    },
    .{
        .path = "/examples/wasm",
        .page = wrapPage(@import(".zx/pages/examples/wasm/page.zig").Page),
        .page_opts = getOptions(@import(".zx/pages/examples/wasm/page.zig"), zx.PageOptions),
        .layout = @import(".zx/pages/examples/wasm/layout.zig").Layout,
    },
    .{
        .path = "/examples/streaming",
        .page = wrapPage(@import(".zx/pages/examples/streaming/page.zig").Page),
        .page_opts = getOptions(@import(".zx/pages/examples/streaming/page.zig"), zx.PageOptions),
    },
    .{
        .path = "/examples/wasm/simple",
        .page = wrapPage(@import(".zx/pages/examples/wasm/simple/page.zig").Page),
        .page_opts = getOptions(@import(".zx/pages/examples/wasm/simple/page.zig"), zx.PageOptions),
    },
    .{
        .path = "/examples/wasm/async",
        .page = wrapPage(@import(".zx/pages/examples/wasm/async/page.zig").Page),
        .page_opts = getOptions(@import(".zx/pages/examples/wasm/async/page.zig"), zx.PageOptions),
    },
    .{
        .path = "/examples/react",
        .page = wrapPage(@import(".zx/pages/examples/wasm/react/page.zig").Page),
        .layout = @import(".zx/pages/examples/wasm/layout.zig").Layout,
        .page_opts = getOptions(@import(".zx/pages/examples/wasm/react/page.zig"), zx.PageOptions),
    },
    .{
        .path = "/examples/wasm/progress",
        .page = wrapPage(@import(".zx/pages/examples/wasm/progress/page.zig").Page),
        .page_opts = getOptions(@import(".zx/pages/examples/wasm/progress/page.zig"), zx.PageOptions),
        .route = zx.App.Meta.route(@import(".zx/pages/examples/wasm/progress/route.zig"), @import(".zx/pages/examples/wasm/progress/page.zig")),
        .route_opts = getOptions(@import(".zx/pages/examples/wasm/progress/route.zig"), zx.RouteOptions),
    },
    .{
        .path = "/examples/wasm/hydration",
        .page = wrapPage(@import(".zx/pages/examples/wasm/hydration/page.zig").Page),
        .page_opts = getOptions(@import(".zx/pages/examples/wasm/hydration/page.zig"), zx.PageOptions),
    },
    .{
        .path = "/examples/overview",
        .page = wrapPage(@import(".zx/pages/examples/overview/page.zig").Page),
        .page_opts = getOptions(@import(".zx/pages/examples/overview/page.zig"), zx.PageOptions),
    },
    .{
        .path = "/examples/realtime",
        .page = wrapPage(@import(".zx/pages/examples/realtime/page.zig").Page),
        .page_opts = getOptions(@import(".zx/pages/examples/realtime/page.zig"), zx.PageOptions),
    },
    .{
        .path = "/examples/realtime/ws",
        .route = zx.App.Meta.route(@import(".zx/pages/examples/realtime/ws/route.zig"), null),
        .route_opts = getOptions(@import(".zx/pages/examples/realtime/ws/route.zig"), zx.RouteOptions),
    },
    .{
        .path = "/api",
        .route = zx.App.Meta.route(@import(".zx/routes/api/route.zig"), null),
        .route_opts = getOptions(@import(".zx/routes/api/route.zig"), zx.RouteOptions),
    },
    .{
        .path = "/ws",
        .route = zx.App.Meta.route(@import(".zx/routes/ws/route.zig"), null),
        .route_opts = getOptions(@import(".zx/routes/ws/route.zig"), zx.RouteOptions),
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

fn wrapPage(comptime pageFn: anytype) *const fn (zx.PageContext) anyerror!zx.Component {
    return struct {
        fn wrapper(ctx: zx.PageContext) anyerror!zx.Component {
            return pageFn(ctx);
        }
    }.wrapper;
}
