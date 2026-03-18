const std = @import("std");
const zx = @import("zx");
const pg = @import("Playground.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var aw = std.Io.Writer.Allocating.init(allocator);

    if (!@hasDecl(pg, "Playground")) {
        @compileError("`pub fn Playground` is required");
    }

    const component = resolveComponent(allocator);
    try component.render(&aw.writer);
    try std.fs.File.stdout().writeAll(aw.written());
}

fn resolveComponent(allocator: zx.Allocator) zx.Component {
    const FnInfo = @typeInfo(@TypeOf(pg.Playground)).@"fn";
    const param_count = FnInfo.params.len;
    const FirstParam = FnInfo.params[0].type.?;

    // fn(ctx: *zx.ComponentContext) zx.Component
    if (param_count == 1 and @typeInfo(FirstParam) == .pointer and
        @hasField(@typeInfo(FirstParam).pointer.child, "allocator") and
        @hasField(@typeInfo(FirstParam).pointer.child, "children"))
    {
        const ctx = allocator.create(@typeInfo(FirstParam).pointer.child) catch @panic("OOM");
        ctx.* = .{ .allocator = allocator, .props = {} };
        return pg.Playground(ctx);
    }

    // fn(allocator: zx.Allocator) zx.Component
    if (param_count == 1 and FirstParam == zx.Allocator) {
        return pg.Playground(allocator);
    }

    @compileError("`Playground` must be `fn (*zx.ComponentContext) zx.Component` or `fn (zx.Allocator) zx.Component`");
}
