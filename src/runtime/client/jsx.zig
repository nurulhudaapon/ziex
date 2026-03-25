const zx = @import("../../root.zig");
const std = @import("std");

pub const ComponentOptions = struct {
    children: ?zx.Component,
};

/// EXPERIMENTAL: Using react component within Ziex
pub fn component(
    allocator: zx.Allocator,
    name: []const u8,
    props: anytype,
    options: ComponentOptions,
) zx.Component {
    if (zx.platform == .client) {
        @compileError(
            \\ Client side zx.Component can't have JSX Component as children, 
            \\ Because we the std.json serializer needs to be included in the WASM bundle, which will pollute the
            \\ size of the WASM binary.
            \\
            \\ In the future we may add support component without props.
        );
    }

    const props_json = std.json.Stringify.valueAlloc(options.allocator, props, .{}) catch @panic("OOM");

    var aw: std.Io.Writer.Allocating = .init(allocator);
    if (options.children) |c| c.render(&aw.writer);

    return zx.Component{ .element = .{ .tag = .div, .attributes = &.{
        &.{
            .key = "data-name",
            .value = name,
        },
        &.{
            .key = "data-props",
            .value = props_json,
        },
        &.{
            .key = "data-children",
            .value = if (options.children) |_| aw.written() else null,
        },
    } } };
}
