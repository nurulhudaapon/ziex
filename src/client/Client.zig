pub const Client = @This();

pub const bom = @import("bom.zig");

pub const ComponentMeta = struct {
    type: zx.Ast.ClientComponentMetadata.Type,
    id: []const u8,
    name: []const u8,
    path: []const u8,
    route: ?[]const u8,
    import: *const fn (allocator: std.mem.Allocator) zx.Component,
};

allocator: std.mem.Allocator,
components: []const ComponentMeta,
vtrees: std.StringHashMap(VDOMTree),

const InitOptions = struct {
    components: []const ComponentMeta,
};

pub fn init(allocator: std.mem.Allocator, options: InitOptions) Client {
    return .{
        .allocator = allocator,
        .components = options.components,
        .vtrees = std.StringHashMap(VDOMTree).init(allocator),
    };
}

pub fn deinit(self: *Client) void {
    var iter = self.vtrees.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.deinit(self.allocator);
    }
    self.vtrees.deinit();
}

pub fn info(self: *Client) void {
    if (builtin.mode != .Debug) return;

    const console = Console.init();
    defer console.deinit();

    const title_css = "background-color: #00a8cc; color: white; font-weight: bold; padding: 3px 5px;";
    const version_css = "background-color: #141414; color: white; font-weight: normal; padding: 3px 5px;";

    const format_str = std.fmt.allocPrint(self.allocator, "%cZX%c{s}", .{zx_info.version_string}) catch unreachable;
    defer self.allocator.free(format_str);

    console.log(.{ js.string(format_str), js.string(title_css), js.string(version_css) });
}

pub fn renderAll(self: *Client) void {
    const console = Console.init();
    defer console.deinit();

    for (self.components) |component| {
        self.render(component) catch {};
    }
}

pub fn render(self: *Client, cmp: ComponentMeta) !void {
    const allocator = self.allocator;

    const document = Document.init(allocator);
    defer document.deinit();

    const console = Console.init();
    defer console.deinit();

    // Root Container
    const container = document.getElementById(cmp.id) catch {
        // console.warn(.{ js.string("Container not found for id: "), js.string(cmp.id) });
        return error.ContainerNotFound;
    };
    defer container.deinit();

    const Component = cmp.import(allocator);
    const existing_vtree = self.vtrees.getPtr(cmp.id);

    const is_first_render = existing_vtree == null;
    if (is_first_render) {
        const vtree = VDOMTree.init(allocator, Component);

        try container.appendChild(vtree.vtree.dom);
        try self.vtrees.put(cmp.id, vtree);
        return;
    }

    // Re-render
    if (existing_vtree) |old_vtree| {
        const root_type_changed = !areComponentsSameType(old_vtree.vtree.component, Component);

        if (root_type_changed) {
            const old_root_dom = old_vtree.vtree.dom;

            const new_vtree = VDOMTree.init(allocator, Component);

            try container.replaceChild(new_vtree.vtree.dom, old_root_dom);
            old_vtree.deinit(allocator);
            try self.vtrees.put(cmp.id, new_vtree);
            return;
        }

        // Diff and apply patches
        var patches = try old_vtree.diffWithComponent(allocator, Component);
        defer {
            for (patches.items) |*patch| {
                switch (patch.type) {
                    .UPDATE => {
                        patch.data.UPDATE.attributes.deinit();
                        patch.data.UPDATE.removed_attributes.deinit(allocator);
                    },
                    else => {},
                }
            }
            patches.deinit(allocator);
        }

        try VDOMTree.applyPatches(allocator, patches);

        old_vtree.vtree.component = Component;
    }
}

const zx = @import("../root.zig");
const std = @import("std");
pub const js = @import("js");
const builtin = @import("builtin");
const zx_info = @import("zx_info");
const vtree_mod = @import("vtree.zig");

const VDOMTree = vtree_mod.VDOMTree;
const Patch = vtree_mod.Patch;
const Document = bom.Document;
const Console = bom.Console;
const areComponentsSameType = vtree_mod.areComponentsSameType;
