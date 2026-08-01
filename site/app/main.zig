const builtin = @import("builtin");
const zx = @import("zx");
const Context = @import("Context.zig");

const context: Context = .{ .port = 5588 };
const config: zx.AppConfig = .{ .server = .{ .port = context.port } };

pub fn main(init: zx.Init) !void {
    var app = try zx.App.init(init, zx.io(), zx.allocator, config, context);
    defer app.deinit();

    try app.start();
}

pub const std_options = zx.std_options;
