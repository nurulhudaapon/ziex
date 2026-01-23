pub const VDOMTree = @This();

/// Global counter for unique VElement IDs used for event delegation
var next_velement_id: u64 = 0;

/// Virtual DOM element with component data and DOM reference
pub const VElement = struct {
    id: u64,
    dom: Document.HTMLNode,
    component: zx.Component,
    children: std.ArrayList(VElement),
    key: ?[]const u8 = null,
    parent_dom: ?Document.HTMLElement = null, // Stored for fragments

    fn nextId() u64 {
        const id = next_velement_id;
        next_velement_id += 1;
        return id;
    }

    fn extractKey(component: zx.Component) ?[]const u8 {
        switch (component) {
            .element => |element| {
                if (element.attributes) |attributes| {
                    for (attributes) |attr| {
                        if (std.mem.eql(u8, attr.name, "key")) {
                            return attr.value;
                        }
                    }
                }
            },
            .component_fn => |comp_fn| {
                _ = comp_fn;
            },
            else => {},
        }
        return null;
    }

    fn keysMatch(self: *const VElement, component: zx.Component) bool {
        const key1 = self.key;
        const key2 = extractKey(component);
        if (key1 == null and key2 == null) return true;
        if (key1 == null or key2 == null) return false;
        return std.mem.eql(u8, key1.?, key2.?);
    }

    fn createFromComponent(
        allocator: zx.Allocator,
        document: Document,
        parent_dom: ?Document.HTMLElement,
        component: zx.Component,
        defer_append: bool,
    ) !VElement {
        switch (component) {
            .none => {
                // Create an empty text node for "render nothing"
                const text_node = document.createTextNode("");
                const velement_id = nextId();
                const velement = VElement{
                    .id = velement_id,
                    .dom = .{ .text = text_node },
                    .component = component,
                    .children = std.ArrayList(VElement).empty,
                    .key = null,
                };
                if (!defer_append) {
                    if (parent_dom) |parent| {
                        try parent.appendChild(velement.dom);
                    }
                }
                return velement;
            },
            .element => |element| {
                // Fragment: no DOM element, children rendered directly to parent
                if (element.tag == .fragment) {
                    var velement = VElement{
                        .id = nextId(),
                        .dom = .{ .text = document.createTextNode("") }, // marker
                        .component = component,
                        .children = std.ArrayList(VElement).empty,
                        .key = null,
                        .parent_dom = parent_dom, // Store for patching
                    };

                    // Append marker to parent first
                    if (!defer_append) {
                        if (parent_dom) |parent| {
                            try parent.appendChild(velement.dom);
                        }
                    }

                    // Render children directly to parent_dom
                    if (element.children) |children| {
                        try velement.children.ensureTotalCapacity(allocator, children.len);
                        for (children) |child| {
                            const child_velement = try createFromComponent(allocator, document, parent_dom, child, defer_append);
                            velement.children.appendAssumeCapacity(child_velement);
                        }
                    }

                    return velement;
                }

                const dom_element = document.createElementId(@intFromEnum(element.tag));
                const velement_id = nextId();

                dom_element.setProperty("__zx_ref", velement_id);
                var key: ?[]const u8 = null;

                if (element.attributes) |attributes| {
                    for (attributes) |attr| {
                        if (std.mem.eql(u8, attr.name, "key")) {
                            key = attr.value;
                            continue;
                        }
                        if (attr.name.len >= 2 and std.mem.eql(u8, attr.name[0..2], "on")) continue;
                        const attr_val = if (attr.value) |val| val else "";

                        dom_element.setAttribute(attr.name, attr_val);
                    }
                }

                var velement = VElement{
                    .id = velement_id,
                    .dom = .{ .element = dom_element },
                    .component = component,
                    .children = std.ArrayList(VElement).empty,
                    .key = key,
                };

                if (element.children) |children| {
                    try velement.children.ensureTotalCapacity(allocator, children.len);
                    for (children) |child| {
                        const child_velement = try createFromComponent(allocator, document, dom_element, child, false);
                        velement.children.appendAssumeCapacity(child_velement);
                    }
                }

                if (!defer_append) {
                    if (parent_dom) |parent| {
                        try parent.appendChild(velement.dom);
                    }
                }

                return velement;
            },
            .text => |text| {
                const text_node = document.createTextNode(if (text.len > 0) text else "");
                const velement_id = nextId();

                const velement = VElement{
                    .id = velement_id,
                    .dom = .{ .text = text_node },
                    .component = component,
                    .children = std.ArrayList(VElement).empty,
                    .key = null,
                };

                if (!defer_append) {
                    if (parent_dom) |parent| {
                        try parent.appendChild(velement.dom);
                    }
                }

                return velement;
            },
            .component_fn => |comp_fn| {
                const resolved = try comp_fn.callFn(comp_fn.propsPtr, allocator);
                var velement = try createFromComponent(allocator, document, parent_dom, resolved, defer_append);
                if (velement.key == null) {
                    velement.key = extractKey(resolved);
                }
                return velement;
            },
            .component_csr => |component_csr| {
                const dom_element = document.createElement("div");
                const velement_id = nextId();

                dom_element.setProperty("__zx_ref", velement_id);
                dom_element.setAttribute("id", component_csr.id);
                dom_element.setAttribute("data-name", component_csr.name);

                const velement = VElement{
                    .id = velement_id,
                    .dom = .{ .element = dom_element },
                    .component = component,
                    .children = std.ArrayList(VElement).empty,
                    .key = null,
                };

                if (!defer_append) {
                    if (parent_dom) |parent| {
                        try parent.appendChild(velement.dom);
                    }
                }

                return velement;
            },
            .signal_text => |sig| {
                const text_node = document.createTextNode(sig.current_text);
                const velement_id = nextId();

                text_node.setProperty("__zx_ref", velement_id);

                const reactivity = @import("reactivity.zig");
                reactivity.registerBinding(sig.signal_id, text_node.ref);

                const velement = VElement{
                    .id = velement_id,
                    .dom = .{ .text = text_node },
                    .component = component,
                    .children = std.ArrayList(VElement).empty,
                    .key = null,
                };

                if (!defer_append) {
                    if (parent_dom) |parent| {
                        try parent.appendChild(velement.dom);
                    }
                }

                return velement;
            },
        }
    }

    pub fn appendChild(self: *VElement, allocator: zx.Allocator, child: VElement) !void {
        switch (self.dom) {
            .element => |element| {
                try element.appendChild(child.dom);
            },
            .text => {
                return error.CannotAppendToTextNode;
            },
        }
        try self.children.append(allocator, child);
    }

    pub fn deinit(self: *VElement, allocator: zx.Allocator) void {
        self.dom.deinit();
        for (self.children.items) |*child| {
            child.deinit(allocator);
        }
        self.children.deinit(allocator);
    }

    /// Get the actual DOM parent element (uses stored parent for fragments)
    pub fn getDomParent(self: *const VElement) ?Document.HTMLElement {
        return switch (self.dom) {
            .element => |elem| elem,
            .text => self.parent_dom, // For fragments, use stored parent
        };
    }
};

pub const PatchType = enum {
    UPDATE,
    PLACEMENT,
    DELETION,
    REPLACE,
    MOVE,
};

pub const PatchData = union(PatchType) {
    UPDATE: struct {
        velement: *VElement,
        attributes: std.StringHashMap([]const u8),
        removed_attributes: std.ArrayList([]const u8),
    },
    PLACEMENT: struct {
        velement: VElement,
        parent: *VElement,
        reference: ?Document.HTMLNode,
        index: usize,
    },
    DELETION: struct {
        velement: *VElement,
        parent: *VElement,
    },
    REPLACE: struct {
        old_velement: *VElement,
        new_velement: VElement,
        parent: *VElement,
    },
    MOVE: struct {
        velement: *VElement,
        parent: *VElement,
        reference: ?Document.HTMLNode,
        new_index: usize,
    },
};

pub const Patch = struct {
    type: PatchType,
    data: PatchData,
};

pub const DiffError = error{
    CSRComponentNotSupported,
    OutOfMemory,
    CannotAppendToTextNode,
};

vtree: VElement,

pub fn init(allocator: zx.Allocator, component: zx.Component) VDOMTree {
    const document = Document.init(allocator);
    const root_velement = VElement.createFromComponent(allocator, document, null, component, true) catch @panic("Error creating root VElement");
    return VDOMTree{ .vtree = root_velement };
}

pub fn diff(
    allocator: zx.Allocator,
    old_velement: *VElement,
    new_component: zx.Component,
    parent: ?*VElement,
    patches: *std.ArrayList(Patch),
) anyerror!void {
    // Resolve component functions to get the real element
    const resolved_component = try resolveComponent(allocator, new_component);

    if (!areComponentsSameType(old_velement.component, resolved_component)) {
        if (parent) |p| {
            try patches.append(allocator, Patch{
                .type = .REPLACE,
                .data = .{
                    .REPLACE = .{
                        .old_velement = old_velement,
                        .new_velement = try createVElementFromComponent(allocator, resolved_component),
                        .parent = p,
                    },
                },
            });
        }
        return;
    }

    switch (resolved_component) {
        .element => |new_element| {
            switch (old_velement.component) {
                .element => |old_element| {
                    var attributes_to_update = std.StringHashMap([]const u8).init(allocator);
                    var attributes_to_remove = std.ArrayList([]const u8).empty;

                    if (old_element.attributes) |old_attrs| {
                        for (old_attrs) |old_attr| {
                            if (std.mem.eql(u8, old_attr.name, "key")) continue;
                            if (old_attr.name.len >= 2 and std.mem.eql(u8, old_attr.name[0..2], "on")) continue;

                            var found = false;
                            if (new_element.attributes) |new_attrs| {
                                for (new_attrs) |new_attr| {
                                    if (std.mem.eql(u8, old_attr.name, new_attr.name)) {
                                        found = true;
                                        const old_val = old_attr.value orelse "";
                                        const new_val = new_attr.value orelse "";
                                        if (!std.mem.eql(u8, old_val, new_val)) {
                                            try attributes_to_update.put(new_attr.name, new_val);
                                        }
                                        break;
                                    }
                                }
                            }

                            if (!found) {
                                try attributes_to_remove.append(allocator, old_attr.name);
                            }
                        }
                    }

                    if (new_element.attributes) |new_attrs| {
                        for (new_attrs) |new_attr| {
                            if (std.mem.eql(u8, new_attr.name, "key")) continue;
                            if (new_attr.name.len >= 2 and std.mem.eql(u8, new_attr.name[0..2], "on")) continue;

                            var found = false;
                            if (old_element.attributes) |old_attrs| {
                                for (old_attrs) |old_attr| {
                                    if (std.mem.eql(u8, old_attr.name, new_attr.name)) {
                                        found = true;
                                        break;
                                    }
                                }
                            }
                            if (!found) {
                                try attributes_to_update.put(new_attr.name, new_attr.value orelse "");
                            }
                        }
                    }

                    if (attributes_to_update.count() > 0 or attributes_to_remove.items.len > 0) {
                        try patches.append(allocator, Patch{
                            .type = .UPDATE,
                            .data = .{
                                .UPDATE = .{
                                    .velement = old_velement,
                                    .attributes = attributes_to_update,
                                    .removed_attributes = attributes_to_remove,
                                },
                            },
                        });
                    }

                    old_velement.component = resolved_component;
                    old_velement.key = VElement.extractKey(resolved_component);

                    try diffChildrenKeyed(allocator, old_velement, resolved_component, old_velement, patches);
                },
                else => {},
            }
        },
        .text => |new_text| {
            switch (old_velement.component) {
                .text => |old_text| {
                    if (!std.mem.eql(u8, old_text, new_text)) {
                        switch (old_velement.dom) {
                            .text => |text_node| {
                                text_node.setNodeValue(if (new_text.len > 0) new_text else "");
                            },
                            else => {},
                        }
                        old_velement.component = .{ .text = new_text };
                    }
                },
                else => {},
            }
        },
        else => {},
    }
}

const IndexedVElement = struct {
    velement: *VElement,
    index: usize,
};

/// Key-based child reconciliation (React-style)
fn resolveComponent(allocator: zx.Allocator, component: zx.Component) !zx.Component {
    var curr = component;
    while (true) {
        switch (curr) {
            .component_fn => |comp_fn| {
                curr = try comp_fn.callFn(comp_fn.propsPtr, allocator);
            },
            else => return curr,
        }
    }
}

fn diffChildrenKeyed(
    allocator: zx.Allocator,
    old_velement: *VElement,
    new_component: zx.Component,
    parent: *VElement,
    patches: *std.ArrayList(Patch),
) !void {
    var old_children = old_velement.children.items;
    const new_children_slice = if (new_component == .element) blk: {
        const element = new_component.element;
        if (element.children) |children| {
            break :blk children;
        } else {
            break :blk &[_]zx.Component{};
        }
    } else &[_]zx.Component{};

    var i: usize = 0; // Start index
    var old_end = old_children.len;
    var new_end = new_children_slice.len;

    var old_start_vnode = if (old_end > 0) &old_children[0] else null;
    var new_start_component = if (new_end > 0) new_children_slice[0] else null;
    var old_end_vnode = if (old_end > 0) &old_children[old_end - 1] else null;
    var new_end_component = if (new_end > 0) new_children_slice[new_end - 1] else null;

    // 1. Sync Prefix
    while (old_start_vnode != null and new_start_component != null) {
        const resolved_child = try resolveComponent(allocator, new_start_component.?);
        if (!areComponentsSameType(old_start_vnode.?.component, resolved_child) or
            !old_start_vnode.?.keysMatch(resolved_child))
        {
            break;
        }

        try diff(allocator, old_start_vnode.?, resolved_child, parent, patches);

        i += 1;
        if (i >= old_end or i >= new_end) break;
        old_start_vnode = &old_children[i];
        new_start_component = new_children_slice[i];
    }

    // 2. Sync Suffix
    while (old_start_vnode != null and new_end_component != null and old_end > i and new_end > i) {
        const resolved_child = try resolveComponent(allocator, new_end_component.?);
        if (!areComponentsSameType(old_end_vnode.?.component, resolved_child) or
            !old_end_vnode.?.keysMatch(resolved_child))
        {
            break;
        }

        try diff(allocator, old_end_vnode.?, resolved_child, parent, patches);

        old_end -= 1;
        new_end -= 1;
        if (old_end <= i or new_end <= i) break;
        old_end_vnode = &old_children[old_end - 1];
        new_end_component = new_children_slice[new_end - 1];
    }

    // 3. Common sequence complete?
    if (i >= old_end) {
        if (i < new_end) {
            // New items are remaining: Add them
            // We need to resolve the reference node properly for the patches.
            // But existing Patch structure uses `?HTMLNode`.
            const reference_html_node: ?Document.HTMLNode = if (old_end < old_children.len)
                old_children[old_end].dom
            else
                null;

            while (i < new_end) : (i += 1) {
                const resolved = try resolveComponent(allocator, new_children_slice[i]);
                const new_child = try createVElementFromComponent(allocator, resolved);
                try patches.append(allocator, Patch{
                    .type = .PLACEMENT,
                    .data = .{
                        .PLACEMENT = .{
                            .velement = new_child,
                            .parent = parent,
                            .reference = reference_html_node,
                            .index = i, // Note: index in VElement children? Not widely used.
                        },
                    },
                });
            }
        }
    } else if (i >= new_end) {
        // Old items are remaining: Remove them
        while (i < old_end) : (i += 1) {
            try patches.append(allocator, Patch{
                .type = .DELETION,
                .data = .{
                    .DELETION = .{
                        .velement = &old_children[i],
                        .parent = parent,
                    },
                },
            });
        }
    } else {
        // 4. Unknown sequence: LIS algorithm
        const old_remainder = old_children[i..old_end];
        const new_remainder = new_children_slice[i..new_end];

        // Map key -> old_indices
        var key_map = std.StringHashMap(usize).init(allocator); // key -> index in old_children
        defer key_map.deinit();

        for (old_remainder, i..) |*c, idx| {
            if (c.key) |k| {
                try key_map.put(k, idx);
            }
        }

        const new_cnt = new_remainder.len;

        var source = try allocator.alloc(isize, new_cnt);
        defer allocator.free(source);
        @memset(source, -1);

        for (new_remainder, 0..) |nc, new_idx| {
            const resolved = try resolveComponent(allocator, nc);
            const k = VElement.extractKey(resolved);
            var matched: bool = false;

            if (k) |key| {
                if (key_map.get(key)) |old_idx| {
                    // Verify type matches
                    if (areComponentsSameType(old_children[old_idx].component, resolved)) {
                        try diff(allocator, &old_children[old_idx], resolved, parent, patches);
                        source[new_idx] = @intCast(old_idx);
                        matched = true;
                    }
                }
            }

            if (!matched) {
                // Try to find non-keyed match? simplified: assume new if no key match
                // For fully keyed application this is fine.
            }
        }

        // Removing unused old items
        var moved_src = try allocator.alloc(bool, old_remainder.len);
        defer allocator.free(moved_src);
        @memset(moved_src, false);

        for (source) |s| {
            if (s != -1) {
                if (s >= i) {
                    moved_src[@as(usize, @intCast(s)) - i] = true;
                }
            }
        }

        for (moved_src, i..) |used, idx| {
            if (!used) {
                try patches.append(allocator, Patch{
                    .type = .DELETION,
                    .data = .{
                        .DELETION = .{
                            .velement = &old_children[idx],
                            .parent = parent,
                        },
                    },
                });
            }
        }

        // Calculate Longest Increasing Subsequence
        const seq = try getLis(allocator, source);
        defer allocator.free(seq);

        var seq_ptr = seq.len;

        // Iterate backwards through new_remainder
        var k: usize = new_cnt;

        var last_processed_dom: ?Document.HTMLNode = if (new_end < old_children.len) old_children[new_end].dom else null;

        k = new_cnt;
        while (k > 0) {
            k -= 1;
            const s = source[k];
            const new_pos = i + k;

            if (s == -1) {
                // New Item
                const resolved = try resolveComponent(allocator, new_remainder[k]);
                const new_child = try createVElementFromComponent(allocator, resolved);

                const dom_ref = new_child.dom;

                try patches.append(allocator, Patch{
                    .type = .PLACEMENT,
                    .data = .{
                        .PLACEMENT = .{
                            .velement = new_child,
                            .parent = parent,
                            .reference = last_processed_dom,
                            .index = new_pos,
                        },
                    },
                });
                last_processed_dom = dom_ref;
            } else {
                // Existing Item
                if (seq_ptr > 0 and seq[seq_ptr - 1] == k) {
                    last_processed_dom = old_children[@as(usize, @intCast(s))].dom;
                    seq_ptr -= 1;
                } else {
                    const velem = &old_children[@as(usize, @intCast(s))];
                    try patches.append(allocator, Patch{
                        .type = .MOVE,
                        .data = .{
                            .MOVE = .{
                                .velement = velem,
                                .parent = parent,
                                .reference = last_processed_dom,
                                .new_index = new_pos,
                            },
                        },
                    });
                    last_processed_dom = velem.dom;
                }
            }
        }
    }
}

// Longest Increasing Subsequence
// Returns indices in `source` that strictly increase.
// Source contains indices >= 0. -1 is ignored.
fn getLis(allocator: zx.Allocator, source: []const isize) ![]const usize {
    var result = std.ArrayList(usize).empty;
    var p = try allocator.alloc(isize, source.len); // Predecessor
    defer allocator.free(p);
    var m = try allocator.alloc(usize, source.len + 1); // Indices of ends of sequences
    defer allocator.free(m);

    var len: usize = 0;

    for (source, 0..) |n, i| {
        if (n == -1) continue;

        // Binary search
        var lo: usize = 1;
        var hi: usize = len;
        while (lo <= hi) {
            const mid = lo + (hi - lo) / 2;
            if (source[m[mid]] < n) {
                lo = mid + 1;
            } else {
                hi = mid - 1;
            }
        }

        const newL = lo;
        p[i] = if (newL > 1) @as(isize, @intCast(m[newL - 1])) else -1;
        m[newL] = i;

        if (newL > len) {
            len = newL;
        }
    }

    var k = if (len > 0) @as(isize, @intCast(m[len])) else -1;
    var i: usize = len;
    try result.resize(allocator, len);

    while (i > 0) {
        i -= 1;
        result.items[i] = @as(usize, @intCast(k));
        k = p[@as(usize, @intCast(k))];
    }

    return result.toOwnedSlice(allocator);
}

pub fn areComponentsSameType(old: zx.Component, new: zx.Component) bool {
    switch (old) {
        .none => {
            return new == .none;
        },
        .element => |old_elem| {
            switch (new) {
                .element => |new_elem| return old_elem.tag == new_elem.tag,
                else => return false,
            }
        },
        .text => {
            switch (new) {
                .text => return true,
                else => return false,
            }
        },
        .component_fn => {
            switch (new) {
                .component_fn => return true,
                else => return false,
            }
        },
        .component_csr => {
            switch (new) {
                .component_csr => return true,
                else => return false,
            }
        },
        .signal_text => |old_sig| {
            switch (new) {
                .signal_text => |new_sig| return old_sig.signal_id == new_sig.signal_id,
                else => return false,
            }
        },
    }
}

fn cloneVElement(allocator: zx.Allocator, velement: *const VElement) !VElement {
    const document = Document.init(allocator);
    var cloned = try VElement.createFromComponent(allocator, document, null, velement.component, true);
    cloned.key = velement.key;
    return cloned;
}

fn createVElementFromComponent(allocator: zx.Allocator, component: zx.Component) !VElement {
    const document = Document.init(allocator);
    return try VElement.createFromComponent(allocator, document, null, component, true);
}

/// Pre-collected patch data to avoid pointer invalidation during batch operations
const DeletionInfo = struct {
    velement_id: u64,
    velement_dom: Document.HTMLNode,
    parent: *VElement,
};

const ReplaceInfo = struct {
    old_velement_id: u64,
    old_velement_dom: Document.HTMLNode,
    new_velement: VElement,
    parent: *VElement,
};

const MoveInfo = struct {
    velement_id: u64,
    velement_dom: Document.HTMLNode,
    parent: *VElement,
    reference: ?Document.HTMLNode,
    new_index: usize,
};

pub fn applyPatches(
    allocator: zx.Allocator,
    patches: std.ArrayList(Patch),
) !void {
    // Pre-collect data before modifications to avoid pointer invalidation
    var deletion_infos = std.ArrayList(DeletionInfo).empty;
    defer deletion_infos.deinit(allocator);

    var replace_infos = std.ArrayList(ReplaceInfo).empty;
    defer replace_infos.deinit(allocator);

    var move_infos = std.ArrayList(MoveInfo).empty;
    defer move_infos.deinit(allocator);

    for (patches.items) |patch| {
        switch (patch.type) {
            .DELETION => {
                const d = patch.data.DELETION;
                try deletion_infos.append(allocator, .{
                    .velement_id = d.velement.id,
                    .velement_dom = d.velement.dom,
                    .parent = d.parent,
                });
            },
            .REPLACE => {
                const r = patch.data.REPLACE;
                try replace_infos.append(allocator, .{
                    .old_velement_id = r.old_velement.id,
                    .old_velement_dom = r.old_velement.dom,
                    .new_velement = r.new_velement,
                    .parent = r.parent,
                });
            },
            .MOVE => {
                const m = patch.data.MOVE;
                try move_infos.append(allocator, .{
                    .velement_id = m.velement.id,
                    .velement_dom = m.velement.dom,
                    .parent = m.parent,
                    .reference = m.reference,
                    .new_index = m.new_index,
                });
            },
            else => {},
        }
    }

    var deletion_idx: usize = 0;
    var replace_idx: usize = 0;
    var move_idx: usize = 0;

    const document = Document.init(allocator);

    var patch_idx: usize = 0;
    while (patch_idx < patches.items.len) {
        const patch = patches.items[patch_idx];
        const current_idx = patch_idx;
        patch_idx += 1;

        switch (patch.type) {
            .UPDATE => {
                const update_data = patch.data.UPDATE;
                const velement = update_data.velement;

                switch (velement.dom) {
                    .element => |element| {
                        var attr_iter = update_data.attributes.iterator();
                        while (attr_iter.next()) |entry| {
                            element.setAttribute(entry.key_ptr.*, entry.value_ptr.*);
                        }

                        for (update_data.removed_attributes.items) |attr_name| {
                            element.removeAttribute(attr_name);
                        }
                    },
                    .text => {},
                }
            },
            .PLACEMENT => {
                const placement_data = patch.data.PLACEMENT;
                const parent = placement_data.parent;
                const parent_element = parent.getDomParent() orelse return error.CannotAppendToTextNode;

                // Check if we can batch consecutive PLACEMENTS (appends only)
                var batched = false;
                if (placement_data.reference == null) {
                    var batch_count: usize = 1;
                    var end_idx = patch_idx; // next patch

                    while (end_idx < patches.items.len) {
                        const next_patch = patches.items[end_idx];
                        if (next_patch.type == .PLACEMENT) {
                            const next_data = next_patch.data.PLACEMENT;
                            if (next_data.parent == parent and next_data.reference == null) {
                                batch_count += 1;
                                end_idx += 1;
                                continue;
                            }
                        }
                        break;
                    }

                    if (batch_count > 1) {
                        batched = true;
                        const fragment = document.createDocumentFragment();

                        // Append all to fragment from VElements that are already fully built (with their children)
                        var i: usize = current_idx;
                        while (i < end_idx) : (i += 1) {
                            const p = patches.items[i].data.PLACEMENT;
                            try fragment.appendChild(p.velement.dom);
                        }

                        // Single append to DOM
                        try parent_element.appendChild(.{ .element = fragment });

                        // Update VTree structure
                        try parent.children.ensureTotalCapacity(allocator, parent.children.items.len + (end_idx - current_idx));
                        i = current_idx;
                        while (i < end_idx) : (i += 1) {
                            const p = patches.items[i].data.PLACEMENT;
                            const index = @min(p.index, parent.children.items.len);
                            try parent.children.insert(allocator, index, p.velement);
                        }

                        patch_idx = end_idx;
                    }
                }

                if (!batched) {
                    const new_child = placement_data.velement;
                    if (placement_data.reference) |ref_dom| {
                        try parent_element.insertBefore(new_child.dom, ref_dom);
                    } else {
                        try parent_element.appendChild(new_child.dom);
                    }

                    const index = @min(placement_data.index, parent.children.items.len);
                    try parent.children.insert(allocator, index, new_child);
                }
            },
            .DELETION => {
                const info = deletion_infos.items[deletion_idx];
                deletion_idx += 1;

                const parent_element = info.parent.getDomParent() orelse return error.CannotRemoveFromTextNode;
                try parent_element.removeChild(info.velement_dom);

                const children = &info.parent.children;
                for (children.items, 0..) |child, i| {
                    if (child.id == info.velement_id) {
                        var removed = children.orderedRemove(i);
                        removed.deinit(allocator);
                        break;
                    }
                }
            },
            .REPLACE => {
                const info = replace_infos.items[replace_idx];
                replace_idx += 1;

                const parent_element = info.parent.getDomParent() orelse return error.CannotReplaceInTextNode;
                try parent_element.replaceChild(info.new_velement.dom, info.old_velement_dom);

                const children = &info.parent.children;
                for (children.items, 0..) |*child, i| {
                    if (child.id == info.old_velement_id) {
                        var old_child = children.items[i];
                        children.items[i] = info.new_velement;
                        old_child.deinit(allocator);
                        break;
                    }
                }
            },
            .MOVE => {
                const info = move_infos.items[move_idx];
                move_idx += 1;

                const parent_element = info.parent.getDomParent() orelse return error.CannotMoveInTextNode;

                if (info.reference) |ref_dom| {
                    try parent_element.insertBefore(info.velement_dom, ref_dom);
                } else {
                    try parent_element.appendChild(info.velement_dom);
                }

                const children = &info.parent.children;
                var old_idx: ?usize = null;

                for (children.items, 0..) |child, i| {
                    if (child.id == info.velement_id) {
                        old_idx = i;
                        break;
                    }
                }

                if (old_idx) |idx| {
                    const removed = children.orderedRemove(idx);
                    const new_idx = @min(info.new_index, children.items.len);
                    try children.insert(allocator, new_idx, removed);
                }
            },
        }
    }
}

pub fn diffWithComponent(
    self: *VDOMTree,
    allocator: zx.Allocator,
    new_component: zx.Component,
) !std.ArrayList(Patch) {
    var patches = std.ArrayList(Patch).empty;

    // Direct diff against component! No eager creation!
    try diff(allocator, &self.vtree, new_component, null, &patches);

    return patches;
}

pub fn deinit(self: *VDOMTree, allocator: zx.Allocator) void {
    self.vtree.deinit(allocator);
}

pub fn getRootElement(self: *const VDOMTree) ?Document.HTMLElement {
    return switch (self.vtree.dom) {
        .element => |elem| elem,
        .text => null,
    };
}

fn updateVElementComponent(velement: *VElement, new_component: zx.Component) void {
    velement.component = new_component;
    velement.key = VElement.extractKey(new_component);

    switch (new_component) {
        .element => |element| {
            if (element.children) |children| {
                var child_idx: usize = 0;
                for (children) |child_component| {
                    if (child_idx < velement.children.items.len) {
                        updateVElementComponent(&velement.children.items[child_idx], child_component);
                        child_idx += 1;
                    }
                }
            }
        },
        .text => {},
        .component_fn => {},
        .component_csr => {},
    }
}

pub fn updateComponents(self: *VDOMTree, new_component: zx.Component) void {
    updateVElementComponent(&self.vtree, new_component);
}

const zx = @import("../../root.zig");
const std = @import("std");
const Document = zx.client.Document;
