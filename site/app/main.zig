const builtin = @import("builtin");
const zx = @import("zx");

pub fn main() !void {
    var app_ctx = AppCtx{ .port = 5588 };

    var app = try zx.App(*AppCtx).init(zx.allocator, .{ .server = .{ .port = 5588 } }, &app_ctx);
    defer app.deinit();

    try app.start();
}

pub const std_options = zx.std_options;

pub const AppCtx = struct {
    port: u16,
};

pub const configs = .{
    .main_site_url = if (builtin.mode == .Debug or builtin.os.tag == .wasi) "" else zx.info.homepage,
    // Some examples are on the SSR site beacuse the main site is statically generated and some of examples depends on the SSR.
    .ssr_url = if (builtin.mode == .Debug or builtin.os.tag == .wasi) "" else "https://ssr.ziex.dev",
    .ssg_url = if (builtin.mode == .Debug or builtin.os.tag == .wasi) "" else zx.info.homepage,
};
