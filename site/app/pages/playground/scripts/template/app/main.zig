const zx = @import("zx");

pub fn main(init: zx.Init) !void {
    var app = try zx.App.init(init, zx.io(), zx.allocator, .{}, {});
    defer app.deinit();

    try app.start();
}

pub const std_options = zx.std_options;
