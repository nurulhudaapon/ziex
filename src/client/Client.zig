pub const Client = @This();

pub const bom = @import("bom.zig");

pub const ComponentMeta = struct {
    type: zx.Ast.ClientComponentMetadata.Type,
    id: []const u8,
    name: []const u8,
    path: []const u8,
    import: *const fn (allocator: std.mem.Allocator) zx.Component,
};

allocator: std.mem.Allocator,
components: []const ComponentMeta,

const InitOptions = struct {
    components: []const ComponentMeta,
};

pub fn init(allocator: std.mem.Allocator, options: InitOptions) Client {
    return .{
        .allocator = allocator,
        .components = options.components,
    };
}

pub fn info(self: *Client) void {
    if (builtin.mode != .Debug) return;

    const console = Console.init();
    defer console.deinit();

    const title_css = "background-color: #00d9ff; color: white; font-weight: bold; padding: 3px 5px;";
    const version_css = "background-color: #35495e; color: white; font-weight: normal; padding: 3px 5px;";

    const format_str = std.fmt.allocPrint(self.allocator, "%cZX%c{s}", .{zx_info.version_string}) catch unreachable;
    defer self.allocator.free(format_str);

    console.log(.{ js.string(format_str), js.string(title_css), js.string(version_css) });
}

pub fn renderAll(self: *Client) void {
    for (self.components) |component| {
        self.render(component) catch unreachable;
    }
}

pub fn render(self: *Client, cmp: ComponentMeta) !void {
    const allocator = self.allocator;

    const document = try Document.init(allocator);
    defer document.deinit();

    const console = Console.init();
    defer console.deinit();

    const buffer = try allocator.alloc(u8, 1024);
    defer allocator.free(buffer);

    var writer = std.Io.Writer.fixed(buffer);

    const Component = cmp.import(allocator);
    try Component.render(&writer);

    const container = document.getElementById(cmp.id) catch {
        console.log(.{ js.string("Container not found for id: "), js.string(cmp.id) });
        return;
    };
    defer container.deinit();

    try container.setInnerHTML(buffer[0..writer.end]);
}

const zx = @import("../root.zig");
const std = @import("std");
const js = @import("js");
const builtin = @import("builtin");
const zx_info = @import("zx_info");

const Document = bom.Document;
const Console = bom.Console;
