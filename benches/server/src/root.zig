pub const data = @import("data.zig");
pub const handlers = @import("handlers.zig");

pub fn get_about_zx() []const u8 {
    return "ZX is a framework for building web applications with Zig.";
}
