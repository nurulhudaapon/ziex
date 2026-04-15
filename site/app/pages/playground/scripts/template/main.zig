const std = @import("std");
const zx = @import("zx");
const pg = @import("Playground.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var aw = std.Io.Writer.Allocating.init(allocator);

    const type_info = @typeInfo(pg);
    const decls = type_info.@"struct".decls;

    if (decls.len == 0) {
        try std.fs.File.stdout().writeAll(
            \\<pre>
            \\No pub component found in Playground.zig
            \\
            \\Please define component,
            \\with one of the following signatures:
            \\
            \\- pub fn (allocator: zx.Allocator) zx.Component;
            \\- pub fn (ctx: *zx.ComponentContext) zx.Component;
            \\</pre>
        );
        return;
    }

    inline for (decls) |decl| {
        const component = resolveComponent(allocator, decl.name);
        try component.render(&aw.writer, .{});
    }

    try std.fs.File.stdout().writeAll(aw.written());
}

fn resolveComponent(allocator: zx.Allocator, comptime field_name: []const u8) zx.Component {
    const Cmp = @field(pg, field_name);

    switch (@typeInfo(@TypeOf(Cmp))) {
        .@"fn" => |FnInfo| {
            const param_count = FnInfo.params.len;
            const FirstParam = FnInfo.params[0].type.?;

            // fn(ctx: *zx.ComponentContext) zx.Component
            if ((param_count == 1 and @typeInfo(FirstParam) == .pointer and
                @hasField(@typeInfo(FirstParam).pointer.child, "allocator") and
                @hasField(@typeInfo(FirstParam).pointer.child, "children")) or
                (param_count == 1 and FirstParam == zx.Allocator) or
                (param_count == 2 and FirstParam == zx.Allocator))
            {
                const cmp_fn = zx.Client.ComponentMeta.init(Cmp);
                return cmp_fn(allocator, "Playground", null);
            }

            // fn(ctx: zx.PageContext) zx.Component
            if (param_count == 1 and FirstParam == zx.PageContext) {
                const ctx = zx.PageContext{
                    .request = .{
                        .url = "https://ziex.dev/playground",
                        .method = .GET,
                        .pathname = "playground",
                        .headers = .{},
                        .arena = allocator,
                    },
                    .response = .{ .arena = allocator },
                    .allocator = allocator,
                    .arena = allocator,
                };
                return Cmp(ctx);
            }

            // fn(ctx: zx.LayoutContext, children: zx.Component) zx.Component
            if (param_count == 2 and FirstParam == zx.LayoutContext and FnInfo.params[1].type == zx.Component) {
                const ctx = zx.LayoutContext{
                    .request = .{
                        .url = "https://ziex.dev/playground",
                        .method = .GET,
                        .pathname = "playground",
                        .headers = .{},
                        .arena = allocator,
                    },
                    .response = .{ .arena = allocator },
                    .allocator = allocator,
                    .arena = allocator,
                };
                return Cmp(ctx, .none);
            }

            @compileError("`Playground` must be `fn (*zx.ComponentContext) zx.Component` or `fn (zx.Allocator) zx.Component`");
        },

        else => {
            return .none;
        },
    }
}
