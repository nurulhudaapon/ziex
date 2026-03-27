const std = @import("std");
const zx = @import("zx");

test "Style size" {
    const prop_size = @sizeOf(zx.style.StyleProperty);
    const output_size = @sizeOf(zx.style.Style);

    std.debug.print("\n--- Style Metrics (Option A: List of Unions) ---\n", .{});
    std.debug.print("Property Union Size: {d} bytes\n", .{prop_size});
    std.debug.print("Style Output Size:   {d} bytes\n", .{output_size});
    std.debug.print("-------------------------------------------------\n", .{});

    // This is now a comptime-computed StyleOutput
    const s = zx.style.styleInit(.{
        zx.style.display(.flex),
        zx.style.background_color(.hex(0xff0000)),
        zx.style.margin_top(.calc(zx.style.Calc.percent(5).sub(.px(10)))),
    });

    try std.testing.expect(s.css.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, s.class, "zx-"));
}
