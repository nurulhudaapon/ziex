pub const Client = @This();

const window = @import("window.zig");
pub const reactivity = @import("reactivity.zig");
pub const hydration = @import("hydration.zig");

/// Global instance counter for assigning unique IDs to component instances
var instance_counter: u16 = 0;

pub const ComponentMeta = struct {
    type: zx.BuiltinAttribute.Rendering,
    id: []const u8,
    name: []const u8,
    path: []const u8,
    route: ?[]const u8,
    import: *const fn (allocator: std.mem.Allocator, data_zon: ?[]const u8) zx.Component,

    pub fn init(comptime func: anytype) *const fn (std.mem.Allocator, ?[]const u8) zx.Component {
        // TODO: Reuse from root.zig
        const FuncInfo = @typeInfo(@TypeOf(func));

        if (FuncInfo != .@"fn") {
            @compileError("Client.ComponentMeta.init requires a function");
        }

        const param_count = FuncInfo.@"fn".params.len;
        if (param_count < 1 or param_count > 2) {
            @compileError("Component function must have 1 or 2 parameters");
        }

        const FirstParamType = FuncInfo.@"fn".params[0].type.?;
        const first_is_allocator = FirstParamType == std.mem.Allocator;
        const first_is_ctx_ptr = @typeInfo(FirstParamType) == .pointer and
            @hasField(@typeInfo(FirstParamType).pointer.child, "allocator") and
            @hasField(@typeInfo(FirstParamType).pointer.child, "children");

        return &struct {
            /// Normalize any return type (Component, ?Component, !Component, !?Component) to Component
            fn normalizeResult(result: anytype) zx.Component {
                const T = @TypeOf(result);
                if (T == zx.Component) {
                    return result;
                }
                // ?Component -> return .none if null
                if (@typeInfo(T) == .optional) {
                    return result orelse .none;
                }
                // !Component or !?Component
                if (@typeInfo(T) == .error_union) {
                    const payload = result catch |err| {
                        std.log.err("Component error: {}", .{err});
                        return .none;
                    };
                    // Check if payload is optional
                    if (@typeInfo(@TypeOf(payload)) == .optional) {
                        return payload orelse .none;
                    }
                    return payload;
                }
                return result;
            }

            fn wrapper(allocator: std.mem.Allocator, props_json: ?[]const u8) zx.Component {
                // Case 1: Component takes only allocator - fn Component(allocator) Component
                if (first_is_allocator and param_count == 1) {
                    return normalizeResult(func(allocator));
                }

                // Case 2: Component takes allocator and props - fn Component(allocator, props) Component
                if (first_is_allocator and param_count == 2) {
                    const PropsType = FuncInfo.@"fn".params[1].type.?;
                    const props = parsePropsFromJson(PropsType, allocator, props_json);
                    return normalizeResult(func(allocator, props));
                }

                // Case 3: Component takes *ComponentCtx(Props) - fn Component(ctx: *ComponentCtx(Props)) Component
                if (first_is_ctx_ptr) {
                    const CtxType = @typeInfo(FirstParamType).pointer.child;
                    const ctx = allocator.create(CtxType) catch @panic("OOM");
                    ctx.allocator = allocator;
                    ctx.children = null;

                    // Inject unique instance ID for per-instance signal state
                    ctx._id = instance_counter;
                    instance_counter +%= 1; // Wrap around on overflow

                    // Parse props if the context has a props field
                    if (@hasField(CtxType, "props")) {
                        const PropsFieldType = @FieldType(CtxType, "props");
                        if (PropsFieldType != void) {
                            ctx.props = parsePropsFromJson(PropsFieldType, allocator, props_json);
                        }
                    }

                    return normalizeResult(func(ctx));
                }

                // Fallback - should not reach here if compile-time checks pass
                @compileError("Unsupported component signature");
            }
        }.wrapper;
    }

    /// Parse props using the Hydrator module
    const parsePropsFromJson = hydration.parseProps;
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
    // components: []const ComponentMeta,
};

pub fn init(allocator: std.mem.Allocator, _: InitOptions) Client {
    return .{
        .allocator = allocator,
        .components = &zx.components,
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
    // Optimization: Skip map update if pointer hasn't changed
    const existing = self.id_to_velement.get(velement.id);
    if (existing == null or existing.? != velement) {
        self.id_to_velement.put(velement.id, velement) catch {};
    }

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
/// event_ref is a u64 NaN-boxed reference to the JS event object
/// Returns true if a handler was found and called
pub fn dispatchEvent(self: *Client, velement_id: u64, event_type: EventType, event_ref: u64) bool {
    if (self.getHandler(velement_id, event_type)) |handler| {
        const event_context = zx.EventContext.init(event_ref);
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

    const format_str = std.fmt.allocPrint(self.allocator, "%cZX%c{s}", .{zx_info.version}) catch unreachable;
    defer self.allocator.free(format_str);

    console.log(.{ js.string(format_str), js.string(title_css), js.string(version_css) });
}

pub fn renderAll(self: *Client) void {
    // Set global for WASM exports (__zx_eventbridge, etc.)
    global_client = self;

    const console = Console.init();
    defer console.deinit();

    for (self.components) |component| {
        self.render(component) catch {};
    }
}

pub fn render(self: *Client, cmp: ComponentMeta) !void {
    const allocator = self.allocator;

    const document = Document.init(allocator);
    // const console = Console.init();

    // Find component boundary using comment markers <!--$id--> or <!--$id|props-->
    // Props ZON is embedded directly in the start comment for faster extraction
    const marker = document.findCommentMarker(cmp.id) catch return error.ContainerNotFound;

    // Call import with allocator and props_zon from the comment marker
    const Component = cmp.import(allocator, marker.props_zon);
    const existing_vtree = self.vtrees.getPtr(cmp.id);

    // First render (hydration) - replace SSR content with VDOM
    if (existing_vtree == null) {
        const new_vtree = VDOMTree.init(allocator, Component);
        try marker.replaceContent(new_vtree.vtree.dom);
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
            const new_vtree = VDOMTree.init(allocator, Component);
            defer old_vtree.deinit(allocator);

            try marker.replaceContent(new_vtree.vtree.dom);
            try self.vtrees.put(cmp.id, new_vtree);
            return;
        }

        // Diff and apply patches
        var patches = try old_vtree.diffWithComponent(allocator, Component);

        // Debug Info
        // if (builtin.mode == .Debug) {
        //     var aw = std.io.Writer.Allocating.init(allocator);
        //     defer aw.deinit();
        //     // Component.render(&aw.writer) catch @panic("OOM");
        //     // console.log(.{ js.string("VTree: "), js.string(aw.written()) });

        //     const fmt_comp = std.fmt.allocPrint(allocator, "JSON.parse(`{f}`).children[1]", .{Component}) catch @panic("OOM");
        //     console.log(.{try bom.eval(js.Object, fmt_comp)});
        //     aw.clearRetainingCapacity();

        //     for (patches.items) |patch| {
        //         switch (patch.data) {
        //             .UPDATE => |update_data| {
        //                 var attr_iter = update_data.attributes.iterator();
        //                 while (attr_iter.next()) |entry| {
        //                     console.log(.{ js.string("UPDATE: "), js.string(entry.key_ptr.*), js.string(" -> "), js.string(entry.value_ptr.*) });
        //                 }

        //                 for (update_data.removed_attributes.items) |attr| {
        //                     console.log(.{ js.string("REMOVED: "), js.string(attr) });
        //                 }
        //             },
        //             else => {},
        //         }
        //     }

        //     var vtrees_iter = self.vtrees.iterator();
        //     while (vtrees_iter.next()) |entry| {
        //         console.log(.{ js.string("VTREE: "), js.string(entry.key_ptr.*) });
        //     }

        //     // patches.print(allocator, "patches: {s}", .{}) catch @panic("OOM");

        //     // container.setAttribute("data-vtree", vtree_json_str);
        // }

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

// js module is only available when targeting WASM
pub const js = if (builtin.cpu.arch == .wasm32) @import("js") else struct {
    pub const String = []const u8;
    pub const Object = struct {
        pub fn get(_: Object, comptime _: type, _: []const u8) anyerror!Object {
            return error.NotInBrowser;
        }
        pub fn getAlloc(_: Object, comptime _: type, _: std.mem.Allocator, _: []const u8) anyerror![]const u8 {
            return error.NotInBrowser;
        }
        pub fn call(_: Object, comptime T: type, _: []const u8, _: anytype) anyerror!T {
            return error.NotInBrowser;
        }
        pub fn set(_: Object, _: []const u8, _: anytype) anyerror!void {
            return error.NotInBrowser;
        }
    };
    pub const global = struct {
        pub fn get(comptime _: type, _: []const u8) anyerror!Object {
            return error.NotInBrowser;
        }
        pub fn call(comptime T: type, _: []const u8, _: anytype) anyerror!T {
            return error.NotInBrowser;
        }
    };
    pub fn string(_: []const u8) String {
        return "";
    }
};

const zx = @import("../../root.zig");
const vtree_mod = @import("render.zig");

const std = @import("std");
const builtin = @import("builtin");
const zx_info = @import("zx_info");

/// Global client pointer for WASM exports (set automatically in renderAll)
pub var global_client: ?*Client = null;

const VDOMTree = vtree_mod.VDOMTree;
const Patch = vtree_mod.Patch;
const Document = window.Document;
const Console = window.Console;
const areComponentsSameType = vtree_mod.areComponentsSameType;

/// Handle DOM events from JS bridge.
export fn __zx_eventbridge(velement_id: u64, event_type_id: u8, event_ref: u64) void {
    if (builtin.os.tag != .freestanding) return;
    if (global_client) |client| {
        const event_type: EventType = @enumFromInt(event_type_id);
        _ = client.dispatchEvent(velement_id, event_type, event_ref);
    }
}

/// Handle async callbacks (setTimeout, setInterval, fetch) from JS bridge.
export fn __zx_cb(callback_type: u8, callback_id: u64, data_ref: u64) void {
    if (builtin.os.tag != .freestanding) return;

    const cb_type: window.CallbackType = @enumFromInt(callback_type);
    _ = window.dispatchCallback(cb_type, callback_id, data_ref, std.heap.wasm_allocator);
}

/// Custom log function for browser environment that outputs to console.
/// Uses console.info/warn/error which already display the level visually.
pub fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const prefix = if (scope == .default) "" else "(" ++ @tagName(scope) ++ ") ";
    const formatted = std.fmt.allocPrint(zx.client_allocator, prefix ++ format, args) catch return;
    Console.init().strLevel(message_level, formatted);
}
