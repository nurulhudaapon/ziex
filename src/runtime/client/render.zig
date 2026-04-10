const html_util = @import("../../util/html.zig");
const vdom = @import("../core/vdom.zig");

pub const RenderOptions = struct {
    base_path: ?[]const u8 = base_path,
};

pub const VDOMTree = vdom;
pub const VNode = vdom.VNode;
pub const VElement = vdom.VElement;
pub const PatchType = vdom.PatchType;
pub const PatchData = vdom.PatchData;
pub const Patch = vdom.Patch;
pub const DiffError = vdom.DiffError;
pub const areComponentsSameType = vdom.areComponentsSameType;

/// Apply a list of patches to the live DOM.
pub fn applyPatches(
    allocator: zx.Allocator,
    client: anytype, // *Client
    patches: std.ArrayList(Patch),
    options: RenderOptions,
) !void {
    for (patches.items) |*patch| {
        switch (patch.type) {
            .UPDATE => {
                const data = patch.data.UPDATE;
                var attr_iter = data.attributes.iterator();
                while (attr_iter.next()) |entry| {
                    const name = entry.key_ptr.*;
                    const val = entry.value_ptr.*;
                    setAttrOrProp(data.vnode_id, name, val);
                }
                for (data.removed_attributes.items) |name| {
                    ext._ra(data.vnode_id, name.ptr, name.len);
                    // For DOM properties, also reset the property to ensure
                    // the live state is updated (e.g. unchecking a checkbox).
                    if (isDomProperty(name)) {
                        const false_val = "false";
                        ext._sp(data.vnode_id, name.ptr, name.len, false_val.ptr, false_val.len);
                    }
                }
            },
            .TEXT => {
                const data = patch.data.TEXT;
                ext._snv(data.vnode_id, data.new_text.ptr, data.new_text.len);
            },
            .PLACEMENT => {
                const data = &patch.data.PLACEMENT;

                _ = try createPlatformNodes(allocator, data.vnode, client, options);

                if (data.reference_id) |ref_id| {
                    ext._ib(data.parent_id, data.vnode.id, ref_id);
                } else {
                    ext._ac(data.parent_id, data.vnode.id);
                }

                if (client.getVElementById(data.parent_id)) |parent_vnode| {
                    const index = @min(data.index, parent_vnode.children.items.len);
                    try parent_vnode.children.insert(allocator, index, data.vnode);
                }
            },
            .DELETION => {
                const data = patch.data.DELETION;

                ext._rc(data.parent_id, data.vnode_id);

                if (client.getVElementById(data.vnode_id)) |vnode| {
                    client.unregisterVElement(vnode);
                }

                if (client.getVElementById(data.parent_id)) |parent_vnode| {
                    for (parent_vnode.children.items, 0..) |child, i| {
                        if (child.id == data.vnode_id) {
                            var removed = parent_vnode.children.orderedRemove(i);
                            removed.deinit(allocator);
                            break;
                        }
                    }
                }
            },
            .REPLACE => {
                const data = &patch.data.REPLACE;

                _ = try createPlatformNodes(allocator, data.new_vnode, client, options);

                ext._rpc(data.parent_id, data.new_vnode.id, data.old_vnode_id);

                if (client.getVElementById(data.old_vnode_id)) |old_vnode| {
                    client.unregisterVElement(old_vnode);
                }

                if (client.getVElementById(data.parent_id)) |parent_vnode| {
                    for (parent_vnode.children.items, 0..) |child, i| {
                        if (child.id == data.old_vnode_id) {
                            const old = parent_vnode.children.items[i];
                            parent_vnode.children.items[i] = data.new_vnode;
                            old.deinit(allocator);
                            break;
                        }
                    }
                }
            },
            .MOVE => {
                const data = patch.data.MOVE;

                if (data.reference_id) |ref_id| {
                    ext._ib(data.parent_id, data.vnode_id, ref_id);
                } else {
                    ext._ac(data.parent_id, data.vnode_id);
                }

                if (client.getVElementById(data.parent_id)) |parent_vnode| {
                    var old_idx: ?usize = null;
                    for (parent_vnode.children.items, 0..) |child, i| {
                        if (child.id == data.vnode_id) {
                            old_idx = i;
                            break;
                        }
                    }
                    if (old_idx) |idx| {
                        const removed = parent_vnode.children.orderedRemove(idx);
                        const new_idx = @min(data.new_index, parent_vnode.children.items.len);
                        try parent_vnode.children.insert(allocator, new_idx, removed);
                    }
                }
            },
        }
    }
}

/// Context stored on the heap so formActionCallback can find the form by vnode_id.
/// When `bound_states` is non-empty the submission is stateful: bound state values
/// are serialised, sent as `__$states`, and the response updates those states.
const FormActionCtx = struct {
    vnode_id: u64,
    bound_states: []const zx.EventHandler.Bound = &.{},
};

/// Callback context for stateful form action responses.
const FormActionCallbackCtx = struct {
    bound_states: []const zx.EventHandler.Bound,
};

/// Called when a stateful form action response arrives; applies state updates.
fn onFormActionResponse(
    ctx_ptr: *anyopaque,
    response: ?*@import("../core/Fetch.zig").Response,
    _: ?@import("../core/Fetch.zig").FetchError,
) void {
    const cb_ctx: *FormActionCallbackCtx = @ptrCast(@alignCast(ctx_ptr));
    defer zx.client_allocator.destroy(cb_ctx);

    const resp = response orelse return;
    if (resp._body.len == 0) return;

    const states = zx.util.zxon.parse([]const []const u8, zx.client_allocator, resp._body, .{}) catch return;
    for (states, 0..) |state_json, i| {
        if (i >= cb_ctx.bound_states.len) break;
        const bs = cb_ctx.bound_states[i];
        bs.applyJson(bs.state_ptr, state_json);
    }
}

/// onsubmit handler for form elements that carry an action handler.
/// Fire-and-forget when no states are bound; stateful round-trip otherwise.
fn formActionCallback(ctx: *anyopaque, event: zx.client.Event) void {
    if (!is_wasm) return;
    const form_ctx: *FormActionCtx = @ptrCast(@alignCast(ctx));
    event.preventDefault();

    if (form_ctx.bound_states.len == 0) {
        ext._submitFormAction(form_ctx.vnode_id);
        return;
    }

    // Stateful: serialise bound-state values → JSON array → __$states field.
    const alloc = zx.client_allocator;
    var states_list = std.ArrayList([]const u8).empty;
    for (form_ctx.bound_states) |bs| {
        states_list.append(alloc, bs.getJson(alloc, bs.state_ptr)) catch {};
    }
    var aw = std.Io.Writer.Allocating.init(alloc);
    zx.util.zxon.serialize(states_list.items, &aw.writer, .{}) catch {};
    const states_json = aw.written();

    const cb_ctx = alloc.create(FormActionCallbackCtx) catch return;
    cb_ctx.* = .{ .bound_states = form_ctx.bound_states };

    const client_fetch = @import("fetch.zig");
    const fetch_id = client_fetch.allocFetchId(alloc, @ptrCast(cb_ctx), onFormActionResponse) orelse {
        alloc.destroy(cb_ctx);
        return;
    };
    ext._submitFormActionAsync(form_ctx.vnode_id, states_json.ptr, states_json.len, fetch_id);
}

/// Build DOM nodes for a VNode subtree and register every node in the JS
pub fn createPlatformNodes(allocator: zx.Allocator, vnode: *VNode, client: anytype, options: RenderOptions) anyerror!Document.HTMLNode {
    if (!is_wasm) return .{ .text = Document.HTMLText.init(allocator, {}) };

    const resolved_component = try vdom.resolveComponent(allocator, vnode.component, vnode.owner_component_id, 0);

    const node: Document.HTMLNode = switch (resolved_component) {
        .none => blk: {
            const ref_id = ext._ct("".ptr, 0, vnode.id);
            break :blk .{ .text = htmlTextFromRef(allocator, ref_id) };
        },
        .text => |t| blk: {
            const ref_id = ext._ct(t.ptr, t.len, vnode.id);
            break :blk .{ .text = htmlTextFromRef(allocator, ref_id) };
        },
        .element => |elem| blk: {
            const ref_id = ext._ce(@intFromEnum(elem.tag), vnode.id);

            if (elem.attributes) |attrs| {
                var has_action_handler = false;
                var has_method = false;
                var form_bound_states: []const zx.EventHandler.Bound = &.{};

                for (attrs) |attr| {
                    if (std.mem.eql(u8, attr.name, "key")) continue;
                    if (attr.handler) |handler| {
                        if (handler.action_fn != null) {
                            has_action_handler = true;
                            form_bound_states = handler.bound_states;
                        }
                        continue;
                    }
                    if (std.mem.eql(u8, attr.name, "method")) has_method = true;
                    const val = attr.value orelse "";
                    // defaultValue is a DOM property; the HTML attribute equivalent is "value"
                    const attr_name = if (std.mem.eql(u8, attr.name, "defaultValue")) "value" else attr.name;

                    // Prefix href/src/action attributes with base_path when applicable
                    var final_val = val;
                    var prefixed_val: ?[]const u8 = null;
                    if (options.base_path) |bp| {
                        const normalized = html_util.normalizeBasePathForPrefixing(bp);
                        if (normalized) |nb| {
                            const is_prefixable = std.mem.eql(u8, attr_name, "href") or
                                std.mem.eql(u8, attr_name, "src") or
                                std.mem.eql(u8, attr_name, "action");
                            if (is_prefixable and html_util.shouldPrefixPathWithBasePath(nb, val)) {
                                prefixed_val = try std.mem.concat(allocator, u8, &.{ nb, val });
                                final_val = prefixed_val.?;
                            }
                        }
                    }
                    defer if (prefixed_val) |pv| allocator.free(pv);

                    setAttrOrProp(vnode.id, attr_name, final_val);
                }

                // Mimic Next.js: auto-inject method="post" enctype="multipart/form-data"
                // on form elements with an action handler
                if (elem.tag == .form and has_action_handler and !has_method) {
                    const method = "method";
                    const post = "post";
                    ext._sa(vnode.id, method.ptr, method.len, post.ptr, post.len);
                    const enctype_key = "enctype";
                    const enctype_val = "multipart/form-data";
                    ext._sa(vnode.id, enctype_key.ptr, enctype_key.len, enctype_val.ptr, enctype_val.len);
                }

                // Register a synthetic onsubmit handler that POSTs form data to the server
                if (elem.tag == .form and has_action_handler) {
                    const Client = @import("Client.zig");
                    if (allocator.create(FormActionCtx) catch null) |form_ctx| {
                        form_ctx.* = .{ .vnode_id = vnode.id, .bound_states = form_bound_states };
                        client.registerHandler(vnode.id, Client.EventType.submit, zx.EventHandler{
                            .callback = &formActionCallback,
                            .context = @ptrCast(form_ctx),
                        });
                    }
                }
            }

            for (vnode.children.items) |child| {
                _ = try createPlatformNodes(allocator, child, client, options);
                ext._ac(vnode.id, child.id);
            }

            break :blk .{ .element = htmlElementFromRef(allocator, ref_id) };
        },
        .component_csr => |csr| blk: {
            // CSR islands: plain <div id="..." data-name="..."> placeholder.
            const ref_id = ext._ce(@intFromEnum(zx.ElementTag.div), vnode.id);
            ext._sa(vnode.id, "id".ptr, "id".len, csr.id.ptr, csr.id.len);
            ext._sa(vnode.id, "data-name".ptr, "data-name".len, csr.name.ptr, csr.name.len);
            break :blk .{ .element = htmlElementFromRef(allocator, ref_id) };
        },
        .component_fn => unreachable,
    };

    // Register VElement for event delegation (id_to_velement, handler_registry).
    client.registerVElement(vnode);
    return node;
}

inline fn htmlElementFromRef(allocator: zx.Allocator, ref_id: u64) Document.HTMLElement {
    const js = @import("js");
    const val: js.Value = @enumFromInt(ref_id);
    return Document.HTMLElement.init(allocator, js.Object{ .value = val });
}

inline fn htmlTextFromRef(allocator: zx.Allocator, ref_id: u64) Document.HTMLText {
    const js = @import("js");
    const val: js.Value = @enumFromInt(ref_id);
    return Document.HTMLText.init(allocator, js.Object{ .value = val });
}

const is_wasm = @import("window.zig").is_wasm;
const ext = @import("window/extern.zig");
const zx = @import("../../root.zig");
const std = @import("std");
const Document = zx.client.Document;
const zx_options = @import("zx_options");

/// Base path for the application, read from build options at comptime.
pub const base_path: ?[]const u8 = zx_options.app_base_path;

fn isDomProperty(name: []const u8) bool {
    return std.mem.eql(u8, name, "checked") or
        std.mem.eql(u8, name, "value") or
        std.mem.eql(u8, name, "selected") or
        std.mem.eql(u8, name, "muted");
}

fn setAttrOrProp(vnode_id: u64, name: []const u8, val: []const u8) void {
    if (isDomProperty(name)) {
        ext._sp(vnode_id, name.ptr, name.len, val.ptr, val.len);
    } else {
        ext._sa(vnode_id, name.ptr, name.len, val.ptr, val.len);
    }
}
