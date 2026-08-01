const mdzx = @This();

const std = @import("std");

const Component = @import("../Component.zig").Component;
const PageContext = @import("core/App/Router/routing.zig").PageContext;

/// Render this MDZX page module's compiled markdown body.
///
/// Pass `@This()` from the page module. The module must define
/// `pub fn render(allocator: Allocator) Component` (emitted by the
/// MDZX/MD transpiler).
///
/// Example:
/// ```zig
/// var ctx: zx.PageContext = undefined;
/// pub fn Page(c: zx.PageContext) zx.Component {
///     ctx = c;
///     return zx.mdzx.page(@This(), c);
/// }
/// ```
pub fn page(comptime Module: type, ctx: PageContext) Component {
    if (!@hasDecl(Module, "render")) {
        @compileError("zx.mdzx.page(@This(), ctx) requires a module that defines render");
    }
    return Module.render(ctx.arena);
}

/// Render this MDZX component module (typically with `Props`).
///
/// Pass `@This()` and the component context. When the emitted `render`
/// takes `*ComponentCtx(Props)`, this forwards `ctx` directly; when it
/// takes an allocator, this uses `ctx.allocator`.
///
/// Example frontmatter (author does **not** declare `render`):
/// ```zig
/// pub const Props = struct { title: []const u8 };
/// var props: Props = undefined;
/// ```
pub fn component(comptime Module: type, ctx: anytype) Component {
    if (!@hasDecl(Module, "render")) {
        @compileError("zx.mdzx.component(@This(), ctx) requires a module that defines render");
    }
    const render_info = @typeInfo(@TypeOf(Module.render)).@"fn";
    if (render_info.params.len != 1) {
        @compileError("zx.mdzx.component expects render with exactly one parameter");
    }
    const Param = render_info.params[0].type orelse
        @compileError("zx.mdzx.component: render parameter type must be known at comptime");
    if (Param == std.mem.Allocator) {
        return Module.render(ctx.allocator);
    }
    return Module.render(ctx);
}
