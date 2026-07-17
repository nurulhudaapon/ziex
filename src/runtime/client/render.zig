const html_util = @import("../../util/html.zig");
const vdom = @import("../core/vdom.zig");

pub const RenderOptions = struct {
    base_path: ?[]const u8 = base_path,
    dom_parent_id: ?u64 = null,
    marker: ?Document.CommentMarker = null,
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
            .RAW_HTML => {
                const data = patch.data.RAW_HTML;
                ext._srh(data.vnode_id, data.html.ptr, data.html.len);
            },
            .PLACEMENT => {
                const data = &patch.data.PLACEMENT;
                const dom_parent_id = resolveDomParentId(client, data.parent_id);

                const resolved = try vdom.resolveComponent(allocator, data.vnode.component, data.vnode.owner_component_id, 0);
                const placed_is_fragment = resolved == .element and resolved.element.tag == .fragment;

                const create_options = RenderOptions{
                    .base_path = options.base_path,
                    .dom_parent_id = if (placed_is_fragment) dom_parent_id else null,
                    .marker = null,
                };
                _ = try createPlatformNodes(allocator, data.vnode, client, create_options);

                if (!placed_is_fragment) {
                    const ref_id = data.reference_id orelse blk: {
                        if (vnodeIsFragment(client, data.parent_id)) {
                            break :blk findFragmentInsertReference(client, data.parent_id, data.index);
                        }
                        break :blk findChildInsertReference(client, data.parent_id, data.index);
                    };
                    if (ref_id) |reference_id| {
                        ext._ib(dom_parent_id, data.vnode.id, reference_id);
                    } else {
                        ext._ac(dom_parent_id, data.vnode.id);
                    }
                }

                if (client.getVElementById(data.parent_id)) |parent_vnode| {
                    const index = @min(data.index, parent_vnode.children.items.len);
                    try parent_vnode.children.insert(allocator, index, data.vnode);
                }
            },
            .DELETION => {
                const data = patch.data.DELETION;

                if (!vnodeIsFragment(client, data.vnode_id)) {
                    const dom_parent_id = resolveDomParentId(client, data.parent_id);
                    ext._rc(dom_parent_id, data.vnode_id);
                }

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
                const dom_parent_id = resolveDomParentId(client, data.parent_id);

                _ = try createPlatformNodes(allocator, data.new_vnode, client, options);

                if (vnodeIsFragment(client, data.old_vnode_id)) {
                    const ref_id = findFragmentInsertReference(client, data.old_vnode_id, 0);
                    if (ref_id) |reference_id| {
                        ext._ib(dom_parent_id, data.new_vnode.id, reference_id);
                    } else {
                        ext._ac(dom_parent_id, data.new_vnode.id);
                    }
                } else if (vnodeIsFragment(client, data.new_vnode.id)) {
                    ext._rc(dom_parent_id, data.old_vnode_id);
                } else {
                    ext._rpc(dom_parent_id, data.new_vnode.id, data.old_vnode_id);
                }

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
                const dom_parent_id = resolveDomParentId(client, data.parent_id);

                const ref_id = data.reference_id orelse findFragmentInsertReference(client, data.parent_id, data.new_index);
                if (ref_id) |reference_id| {
                    ext._ib(dom_parent_id, data.vnode_id, reference_id);
                } else {
                    ext._ac(dom_parent_id, data.vnode_id);
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
    action_id: u32 = 1,
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
    defer zx.allocator.destroy(cb_ctx);

    const resp = response orelse return;
    if (resp._body.len == 0) return;

    const states = zx.util.zxon.parse([]const []const u8, zx.allocator, resp._body, .{}) catch return;
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
        ext._submitFormAction(form_ctx.vnode_id, form_ctx.action_id);
        return;
    }

    // Stateful: serialise bound-state values → JSON array → __$states field.
    const alloc = zx.allocator;
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
    ext._submitFormActionAsync(form_ctx.vnode_id, form_ctx.action_id, states_json.ptr, states_json.len, fetch_id);
}

/// Build DOM nodes for a VNode subtree and register every node in the JS registry.
/// Returns null for fragment roots (children are mounted individually).
pub fn createPlatformNodes(allocator: zx.Allocator, vnode: *VNode, client: anytype, options: RenderOptions) anyerror!?Document.HTMLNode {
    if (!is_wasm) return .{ .text = Document.HTMLText.init(allocator, {}) };

    const resolved_component = try vdom.resolveComponent(allocator, vnode.component, vnode.owner_component_id, 0);

    const node: ?Document.HTMLNode = switch (resolved_component) {
        .none => blk: {
            const ref_id = ext._ct("".ptr, 0, vnode.id);
            const n: Document.HTMLNode = .{ .text = htmlTextFromRef(allocator, ref_id) };
            try attachCreatedNodeIfNeeded(n, vnode.id, options);
            break :blk n;
        },
        .text => |t| blk: {
            const ref_id = ext._ct(t.ptr, t.len, vnode.id);
            const n: Document.HTMLNode = .{ .text = htmlTextFromRef(allocator, ref_id) };
            try attachCreatedNodeIfNeeded(n, vnode.id, options);
            break :blk n;
        },
        .element => |elem| blk: {
            if (elem.tag == .fragment) {
                client.registerVElement(vnode);
                const child_options = RenderOptions{
                    .base_path = options.base_path,
                    .dom_parent_id = options.dom_parent_id,
                    .marker = null,
                };
                for (vnode.children.items) |child| {
                    _ = try createPlatformNodes(allocator, child, client, child_options);
                }
                break :blk null;
            }

            const ref_id = ext._ce(@intFromEnum(elem.tag), vnode.id);

            if (elem.attributes) |attrs| {
                var has_action_handler = false;
                var has_method = false;
                var form_bound_states: []const zx.EventHandler.Bound = &.{};
                var form_action_id: u32 = 1;
                var client_action_handler: ?zx.EventHandler = null;

                for (attrs) |attr| {
                    if (std.mem.eql(u8, attr.name, "key")) continue;
                    if (attr.handler) |handler| {
                        if (handler.action_fn != null) {
                            has_action_handler = true;
                            form_bound_states = handler.bound_states;
                            form_action_id = handler.handler_id;
                        } else if (std.mem.eql(u8, attr.name, "action")) {
                            client_action_handler = handler;
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
                // on form elements with a server action handler
                if (elem.tag == .form and has_action_handler and !has_method) {
                    const method = "method";
                    const post = "post";
                    ext._sa(vnode.id, method.ptr, method.len, post.ptr, post.len);
                    const enctype_key = "enctype";
                    const enctype_val = "multipart/form-data";
                    ext._sa(vnode.id, enctype_key.ptr, enctype_key.len, enctype_val.ptr, enctype_val.len);
                }

                // Register onsubmit: server actions POST; client actions run handler.callback locally
                if (elem.tag == .form) {
                    const Client = @import("Client.zig");
                    if (has_action_handler) {
                        if (allocator.create(FormActionCtx) catch null) |form_ctx| {
                            form_ctx.* = .{
                                .vnode_id = vnode.id,
                                .action_id = form_action_id,
                                .bound_states = form_bound_states,
                            };
                            client.registerHandler(vnode.id, Client.EventType.submit, zx.EventHandler{
                                .callback = &formActionCallback,
                                .context = @ptrCast(form_ctx),
                            });
                        }
                    } else if (client_action_handler) |handler| {
                        client.registerHandler(vnode.id, Client.EventType.submit, handler);
                    }
                }
            }

            // When escaping is disabled (@escaping={.none}), the element's text
            // children are raw HTML and must be inserted via innerHTML
            if (elem.escaping == .none) {
                var aw = std.Io.Writer.Allocating.init(allocator);
                defer aw.deinit();
                for (vnode.children.items) |child| {
                    const resolved_child = try vdom.resolveComponent(allocator, child.component, child.owner_component_id, 0);
                    switch (resolved_child) {
                        .text => |t| try aw.writer.writeAll(t),
                        .none => {},
                        // Non-text children fall back to normal node creation below.
                        else => {},
                    }
                }
                const raw = aw.written();
                ext._srh(vnode.id, raw.ptr, raw.len);
                const n: Document.HTMLNode = .{ .element = htmlElementFromRef(allocator, ref_id) };
                try attachCreatedNodeIfNeeded(n, vnode.id, options);
                break :blk n;
            }

            for (vnode.children.items) |child| {
                const resolved_child = try vdom.resolveComponent(allocator, child.component, child.owner_component_id, 0);
                const child_options = RenderOptions{
                    .base_path = options.base_path,
                    .dom_parent_id = null,
                    .marker = null,
                };
                if (resolved_child == .element and resolved_child.element.tag == .fragment) {
                    const frag_options = RenderOptions{
                        .base_path = options.base_path,
                        .dom_parent_id = vnode.id,
                        .marker = null,
                    };
                    _ = try createPlatformNodes(allocator, child, client, frag_options);
                } else {
                    _ = try createPlatformNodes(allocator, child, client, child_options);
                    ext._ac(vnode.id, child.id);
                }
            }

            const n: Document.HTMLNode = .{ .element = htmlElementFromRef(allocator, ref_id) };
            try attachCreatedNodeIfNeeded(n, vnode.id, options);
            break :blk n;
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

    if (node) |_| client.registerVElement(vnode);
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
const app_opts = @import("app_opts");

/// Base path for the application, read from build options at comptime.
pub const base_path: ?[]const u8 = app_opts.app_base_path;

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

fn attachCreatedNodeIfNeeded(node: Document.HTMLNode, vnode_id: u64, options: RenderOptions) !void {
    if (options.dom_parent_id != null or options.marker != null) {
        try attachCreatedNode(node, vnode_id, options);
    }
}

fn attachCreatedNode(node: Document.HTMLNode, vnode_id: u64, options: RenderOptions) !void {
    if (options.dom_parent_id) |parent_id| {
        ext._ac(parent_id, vnode_id);
    } else if (options.marker) |marker| {
        try marker.insertContent(node);
    }
}

fn resolveDomParentId(client: anytype, parent_vnode_id: u64) u64 {
    if (client.getVElementById(parent_vnode_id)) |parent| {
        if (parent.component == .element and parent.component.element.tag == .fragment) {
            var vtrees_iter = client.vtrees.iterator();
            while (vtrees_iter.next()) |entry| {
                if (findDomParentInSubtree(entry.value_ptr.vtree, parent_vnode_id, null)) |id| return id;
            }
        }
    }
    return parent_vnode_id;
}

fn vnodeIsFragment(client: anytype, vnode_id: u64) bool {
    if (client.getVElementById(vnode_id)) |vnode| {
        return vnode.component == .element and vnode.component.element.tag == .fragment;
    }
    return false;
}

fn findDomParentInSubtree(node: *VNode, target_id: u64, dom_ancestor: ?u64) ?u64 {
    const dom_here: ?u64 = if (node.component == .element and node.component.element.tag != .fragment)
        node.id
    else
        dom_ancestor;

    if (node.id == target_id) return dom_here;

    for (node.children.items) |child| {
        const next_ancestor: ?u64 = if (node.component == .element and node.component.element.tag != .fragment)
            node.id
        else
            dom_ancestor;
        if (findDomParentInSubtree(child, target_id, next_ancestor)) |found| return found;
    }
    return null;
}

fn firstDomNodeId(vnode: *VNode) ?u64 {
    switch (vnode.component) {
        .element => |elem| {
            if (elem.tag == .fragment) {
                for (vnode.children.items) |child| {
                    if (firstDomNodeId(child)) |id| return id;
                }
                return null;
            }
            return vnode.id;
        },
        .text => return vnode.id,
        else => return null,
    }
}

/// When inserting into a fragment vnode, DOM nodes must be placed before the
/// fragment's next sibling (e.g. conditional `{if ...}` before the following `<p>`).
fn findFragmentInsertReference(client: anytype, fragment_id: u64, insert_index: usize) ?u64 {
    var vtrees_iter = client.vtrees.iterator();
    while (vtrees_iter.next()) |entry| {
        if (findFragmentInsertReferenceInSubtree(entry.value_ptr.vtree, fragment_id, insert_index)) |id| return id;
    }
    return null;
}

fn findFragmentInsertReferenceInSubtree(parent: *VNode, fragment_id: u64, insert_index: usize) ?u64 {
    for (parent.children.items, 0..) |child, i| {
        if (child.id == fragment_id) {
            if (insert_index < child.children.items.len) {
                if (firstDomNodeId(child.children.items[insert_index])) |id| return id;
            }
            if (i + 1 < parent.children.items.len) {
                return firstDomNodeId(parent.children.items[i + 1]);
            }
            return null;
        }
        if (findFragmentInsertReferenceInSubtree(child, fragment_id, insert_index)) |id| return id;
    }
    return null;
}

/// Find the DOM node to insert before when placing a child at `insert_index` in `parent_id`.
fn findChildInsertReference(client: anytype, parent_id: u64, insert_index: usize) ?u64 {
    if (client.getVElementById(parent_id)) |parent| {
        if (insert_index < parent.children.items.len) {
            const at_slot = parent.children.items[insert_index];
            if (vnodeIsFragment(client, at_slot.id)) {
                if (insert_index + 1 < parent.children.items.len) {
                    return firstDomNodeId(parent.children.items[insert_index + 1]);
                }
                return null;
            }
            return firstDomNodeId(at_slot);
        }
    }
    return null;
}
