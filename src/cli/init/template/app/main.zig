const zx = @import("zx");

pub fn main() !void {
    var app = try zx.App(void).init(zx.allocator, .{}, {});
    defer app.deinit();

    try app.start();
}

pub const std_options = zx.std_options;
