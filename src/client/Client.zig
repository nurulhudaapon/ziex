pub const Client = @This();

pub const bom = @import("bom.zig");

pub const ComponentMeta = struct {
    type: zx.BuiltinAttribute.Rendering,
    id: []const u8,
    name: []const u8,
    path: []const u8,
    route: ?[]const u8,
    import: *const fn (allocator: std.mem.Allocator) zx.Component,
};

/// Key for the handler registry: (velement_id, event_type_hash)
const HandlerKey = struct {
    velement_id: u64,
    event_type: EventType,
};

/// Supported event types
pub const EventType = enum(u8) {
    click,
    dblclick,
    input,
    change,
    submit,
    focus,
    blur,
    keydown,
    keyup,
    keypress,
    mouseenter,
    mouseleave,
    mousedown,
    mouseup,
    mousemove,
    touchstart,
    touchend,
    touchmove,
    scroll,

    /// Parse event type from attribute name (e.g., "onclick" -> .click)
    pub fn fromAttributeName(name: []const u8) ?EventType {
        // Event attributes start with "on"
        if (name.len < 3 or !std.mem.startsWith(u8, name, "on")) return null;

        const event_name = name[2..]; // Skip "on" prefix
        return std.meta.stringToEnum(EventType, event_name);
    }
};

allocator: std.mem.Allocator,
components: []const ComponentMeta,
vtrees: std.StringHashMap(VDOMTree),
/// Registry mapping VElement IDs to their VElement pointers for event delegation
id_to_velement: std.AutoHashMap(u64, *vtree_mod.VElement),
/// Registry mapping (velement_id, event_type) to event handlers
/// This is the React-style handler registry - handlers are stored here, not as strings
handler_registry: std.AutoHashMap(HandlerKey, zx.EventHandler),

const InitOptions = struct {
    components: []const ComponentMeta,
};

pub fn init(allocator: std.mem.Allocator, options: InitOptions) Client {
    return .{
        .allocator = allocator,
        .components = options.components,
        .vtrees = std.StringHashMap(VDOMTree).init(allocator),
        .id_to_velement = std.AutoHashMap(u64, *vtree_mod.VElement).init(allocator),
        .handler_registry = std.AutoHashMap(HandlerKey, zx.EventHandler).init(allocator),
    };
}

pub fn deinit(self: *Client) void {
    var iter = self.vtrees.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.deinit(self.allocator);
    }
    self.vtrees.deinit();
    self.id_to_velement.deinit();
    self.handler_registry.deinit();
}

/// Register a VElement and all its children in the id_to_velement registry
/// This enables event delegation lookup by VElement ID
/// Also extracts and registers event handlers from component attributes
pub fn registerVElement(self: *Client, velement: *vtree_mod.VElement) void {
    self.id_to_velement.put(velement.id, velement) catch {};

    // Extract and register event handlers from the component's attributes
    switch (velement.component) {
        .element => |element| {
            if (element.attributes) |attributes| {
                for (attributes) |attr| {
                    // Check if this attribute has a handler (React-style)
                    if (attr.handler) |handler| {
                        // Parse event type from attribute name (e.g., "onclick" -> .click)
                        if (EventType.fromAttributeName(attr.name)) |event_type| {
                            self.registerHandler(velement.id, event_type, handler);
                        }
                    }
                }
            }
        },
        else => {},
    }

    // Recursively register children
    for (velement.children.items) |*child| {
        self.registerVElement(child);
    }
}

/// Register an event handler for a specific VElement and event type
pub fn registerHandler(self: *Client, velement_id: u64, event_type: EventType, handler: zx.EventHandler) void {
    const key = HandlerKey{ .velement_id = velement_id, .event_type = event_type };
    self.handler_registry.put(key, handler) catch {};
}

/// Look up a handler by VElement ID and event type
pub fn getHandler(self: *Client, velement_id: u64, event_type: EventType) ?zx.EventHandler {
    const key = HandlerKey{ .velement_id = velement_id, .event_type = event_type };
    return self.handler_registry.get(key);
}

/// Unregister a VElement and all its children from the registry
pub fn unregisterVElement(self: *Client, velement: *vtree_mod.VElement) void {
    _ = self.id_to_velement.remove(velement.id);

    // Recursively unregister children
    for (velement.children.items) |*child| {
        self.unregisterVElement(child);
    }
}

pub fn getVElementById(self: *Client, id: u64) ?*vtree_mod.VElement {
    return self.id_to_velement.get(id);
}

/// Dispatch an event to the appropriate handler
/// This looks up the handler in the registry and calls it with an EventContext
/// Returns true if a handler was found and called
pub fn dispatchEvent(self: *Client, velement_id: u64, event_type: EventType, event_id: u64) bool {
    if (self.getHandler(velement_id, event_type)) |handler| {
        const event_context = zx.EventContext.init(event_id);
        handler(event_context);
        return true;
    }
    return false;
}

pub fn dispatchEventByName(self: *Client, velement_id: u64, event_type_name: []const u8) bool {
    const event_type = std.meta.stringToEnum(EventType, event_type_name) orelse return false;
    return self.dispatchEvent(velement_id, event_type);
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
    const console = Console.init();

    // Root Container
    const container = document.getElementById(cmp.id) catch return error.ContainerNotFound;

    const Component = cmp.import(allocator);
    const existing_vtree = self.vtrees.getPtr(cmp.id);
    const new_vtree = VDOMTree.init(allocator, Component);

    // First render
    if (existing_vtree == null) {
        try container.appendChild(new_vtree.vtree.dom);
        try self.vtrees.put(cmp.id, new_vtree);

        // Register VElements for event delegation
        if (self.vtrees.getPtr(cmp.id)) |vtree_ptr| {
            self.registerVElement(&vtree_ptr.vtree);
        }
        return;
    }

    // Re-render
    if (existing_vtree) |old_vtree| {
        const root_type_changed = !areComponentsSameType(old_vtree.vtree.component, Component);

        if (root_type_changed) {
            defer old_vtree.deinit(allocator);
            const old_root_dom = old_vtree.vtree.dom;

            try container.replaceChild(new_vtree.vtree.dom, old_root_dom);
            try self.vtrees.put(cmp.id, new_vtree);
            return;
        }

        // Diff and apply patches
        var patches = try old_vtree.diffWithComponent(allocator, Component);

        // Debug Info
        {
            var aw = std.io.Writer.Allocating.init(allocator);
            defer aw.deinit();
            // Component.render(&aw.writer) catch @panic("OOM");
            // console.log(.{ js.string("VTree: "), js.string(aw.written()) });

            const fmt_comp = std.fmt.allocPrint(allocator, "JSON.parse(`{f}`).children[1]", .{Component}) catch @panic("OOM");
            console.log(.{try bom.eval(js.Object, fmt_comp)});
            aw.clearRetainingCapacity();

            for (patches.items) |patch| {
                switch (patch.data) {
                    .UPDATE => |update_data| {
                        var attr_iter = update_data.attributes.iterator();
                        while (attr_iter.next()) |entry| {
                            console.log(.{ js.string("UPDATE: "), js.string(entry.key_ptr.*), js.string(" -> "), js.string(entry.value_ptr.*) });
                        }

                        for (update_data.removed_attributes.items) |attr| {
                            console.log(.{ js.string("REMOVED: "), js.string(attr) });
                        }
                    },
                    else => {},
                }
            }

            var vtrees_iter = self.vtrees.iterator();
            while (vtrees_iter.next()) |entry| {
                console.log(.{ js.string("VTREE: "), js.string(entry.key_ptr.*) });
            }

            // patches.print(allocator, "patches: {s}", .{}) catch @panic("OOM");

            // container.setAttribute("data-vtree", vtree_json_str);
        }

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

        // Re-register VElements to pick up any new elements created by PLACEMENT patches
        // This ensures event handlers are registered for newly created elements
        self.registerVElement(&old_vtree.vtree);

        // Update the VElement tree's components to match the new component
        // This ensures that on the next render, the diff will compare against the updated state
        // old_vtree.updateComponents(Component);
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
