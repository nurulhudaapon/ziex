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

    fn createFromComponent(
        allocator: zx.Allocator,
        document: Document,
        parent_dom: ?Document.HTMLElement,
        component: zx.Component,
    ) !VElement {
        switch (component) {
            .element => |element| {
                const dom_element = document.createElement(@tagName(element.tag));
                const velement_id = nextId();

                dom_element.setProperty("__zx_ref", velement_id);
                const key = extractKey(component);

                if (element.attributes) |attributes| {
                    for (attributes) |attr| {
                        if (std.mem.eql(u8, attr.name, "key")) continue;
                        const attr_val = if (attr.value) |val| val else "true";
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
                    for (children) |child| {
                        const child_velement = try createFromComponent(allocator, document, dom_element, child);
                        try velement.children.append(allocator, child_velement);
                    }
                }

                if (parent_dom) |parent| {
                    try parent.appendChild(velement.dom);
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

                if (parent_dom) |parent| {
                    try parent.appendChild(velement.dom);
                }

                return velement;
            },
            .component_fn => |comp_fn| {
                const resolved = try comp_fn.callFn(comp_fn.propsPtr, allocator);
                var velement = try createFromComponent(allocator, document, parent_dom, resolved);
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
                dom_element.setAttribute("data-props", component_csr.props_json orelse "{}");

                const velement = VElement{
                    .id = velement_id,
                    .dom = .{ .element = dom_element },
                    .component = component,
                    .children = std.ArrayList(VElement).empty,
                    .key = null,
                };

                if (parent_dom) |parent| {
                    try parent.appendChild(velement.dom);
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
        reference: ?*VElement,
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
        reference: ?*VElement,
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
    const root_velement = VElement.createFromComponent(allocator, document, null, component) catch @panic("Error creating root VElement");
    return VDOMTree{ .vtree = root_velement };
}

pub fn diff(
    allocator: zx.Allocator,
    old_velement: *VElement,
    new_velement: *const VElement,
    parent: ?*VElement,
    patches: *std.ArrayList(Patch),
) anyerror!void {
    if (!areComponentsSameType(old_velement.component, new_velement.component)) {
        if (parent) |p| {
            try patches.append(allocator, Patch{
                .type = .REPLACE,
                .data = .{
                    .REPLACE = .{
                        .old_velement = old_velement,
                        .new_velement = try cloneVElement(allocator, new_velement),
                        .parent = p,
                    },
                },
            });
        }
        return;
    }

    switch (new_velement.component) {
        .element => |new_element| {
            switch (old_velement.component) {
                .element => |old_element| {
                    var attributes_to_update = std.StringHashMap([]const u8).init(allocator);
                    var attributes_to_remove = std.ArrayList([]const u8).empty;

                    if (old_element.attributes) |old_attrs| {
                        for (old_attrs) |old_attr| {
                            if (std.mem.eql(u8, old_attr.name, "key")) continue;

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

                    old_velement.component = new_velement.component;
                    old_velement.key = new_velement.key;

                    try diffChildrenKeyed(allocator, old_velement, new_velement, old_velement, patches);
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
fn diffChildrenKeyed(
    allocator: zx.Allocator,
    old_velement: *VElement,
    new_velement: *const VElement,
    parent: *VElement,
    patches: *std.ArrayList(Patch),
) !void {
    const old_children = old_velement.children.items;
    const new_children_components = if (new_velement.component == .element) blk: {
        const element = new_velement.component.element;
        if (element.children) |children| {
            break :blk children;
        } else {
            break :blk &[_]zx.Component{};
        }
    } else &[_]zx.Component{};

    var old_keyed_children = std.StringHashMap(IndexedVElement).init(allocator);
    defer old_keyed_children.deinit();

    var old_matched = try allocator.alloc(bool, old_children.len);
    defer allocator.free(old_matched);
    @memset(old_matched, false);

    var non_keyed_old = std.array_list.Managed(IndexedVElement).init(allocator);
    defer non_keyed_old.deinit();

    for (old_children, 0..) |*old_child, i| {
        if (old_child.key) |k| {
            try old_keyed_children.put(k, .{ .velement = old_child, .index = i });
        } else {
            try non_keyed_old.append(.{ .velement = old_child, .index = i });
        }
    }

    var new_velements = try allocator.alloc(VElement, new_children_components.len);
    defer {
        for (new_velements) |*nv| {
            nv.deinit(allocator);
        }
        allocator.free(new_velements);
    }

    for (new_children_components, 0..) |new_child_component, i| {
        new_velements[i] = try createVElementFromComponent(allocator, new_child_component);
    }

    var last_placed_index: isize = -1;
    var non_keyed_idx: usize = 0;

    for (new_velements, 0..) |*new_child_velement, new_idx| {
        var matched_old: ?IndexedVElement = null;

        if (new_child_velement.key) |new_key| {
            if (old_keyed_children.get(new_key)) |old_entry| {
                matched_old = old_entry;
                old_matched[old_entry.index] = true;
            }
        } else {
            while (non_keyed_idx < non_keyed_old.items.len) {
                const candidate = non_keyed_old.items[non_keyed_idx];
                non_keyed_idx += 1;

                if (!old_matched[candidate.index]) {
                    if (areComponentsSameType(candidate.velement.component, new_child_velement.component)) {
                        matched_old = candidate;
                        old_matched[candidate.index] = true;
                        break;
                    }
                }
            }
        }

        if (matched_old) |old_entry| {
            const old_child = old_entry.velement;
            const old_idx = old_entry.index;

            try diff(allocator, old_child, new_child_velement, parent, patches);

            const old_idx_signed: isize = @intCast(old_idx);
            if (old_idx_signed < last_placed_index) {
                const reference = if (new_idx + 1 < old_children.len)
                    &old_velement.children.items[new_idx + 1]
                else
                    null;

                try patches.append(allocator, Patch{
                    .type = .MOVE,
                    .data = .{
                        .MOVE = .{
                            .velement = old_child,
                            .parent = parent,
                            .reference = reference,
                            .new_index = new_idx,
                        },
                    },
                });
            }

            last_placed_index = @max(last_placed_index, old_idx_signed);
        } else {
            const new_child = try cloneVElement(allocator, new_child_velement);
            const reference = if (new_idx < old_velement.children.items.len)
                &old_velement.children.items[new_idx]
            else
                null;

            try patches.append(allocator, Patch{
                .type = .PLACEMENT,
                .data = .{
                    .PLACEMENT = .{
                        .velement = new_child,
                        .parent = parent,
                        .reference = reference,
                        .index = new_idx,
                    },
                },
            });
        }
    }

    for (old_matched, 0..) |matched, i| {
        if (!matched) {
            try patches.append(allocator, Patch{
                .type = .DELETION,
                .data = .{
                    .DELETION = .{
                        .velement = &old_velement.children.items[i],
                        .parent = parent,
                    },
                },
            });
        }
    }
}

pub fn areComponentsSameType(old: zx.Component, new: zx.Component) bool {
    switch (old) {
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
    }
}

fn cloneVElement(allocator: zx.Allocator, velement: *const VElement) !VElement {
    const document = Document.init(allocator);
    var cloned = try VElement.createFromComponent(allocator, document, null, velement.component);
    cloned.key = velement.key;
    return cloned;
}

fn createVElementFromComponent(allocator: zx.Allocator, component: zx.Component) !VElement {
    const document = Document.init(allocator);
    return try VElement.createFromComponent(allocator, document, null, component);
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
    reference: ?*VElement,
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

    for (patches.items) |patch| {
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
                const new_child = placement_data.velement;

                switch (parent.dom) {
                    .element => |parent_element| {
                        if (placement_data.reference) |ref| {
                            switch (ref.dom) {
                                .element => |ref_element| {
                                    try parent_element.insertBefore(new_child.dom, .{ .element = ref_element });
                                },
                                .text => |ref_text| {
                                    try parent_element.insertBefore(new_child.dom, .{ .text = ref_text });
                                },
                            }
                        } else {
                            try parent_element.appendChild(new_child.dom);
                        }

                        const index = @min(placement_data.index, parent.children.items.len);
                        try parent.children.insert(allocator, index, new_child);
                    },
                    .text => {
                        return error.CannotAppendToTextNode;
                    },
                }
            },
            .DELETION => {
                const info = deletion_infos.items[deletion_idx];
                deletion_idx += 1;

                switch (info.parent.dom) {
                    .element => |parent_element| {
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
                    .text => {
                        return error.CannotRemoveFromTextNode;
                    },
                }
            },
            .REPLACE => {
                const info = replace_infos.items[replace_idx];
                replace_idx += 1;

                switch (info.parent.dom) {
                    .element => |parent_element| {
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
                    .text => {
                        return error.CannotReplaceInTextNode;
                    },
                }
            },
            .MOVE => {
                const info = move_infos.items[move_idx];
                move_idx += 1;

                switch (info.parent.dom) {
                    .element => |parent_element| {
                        if (info.reference) |ref| {
                            try parent_element.insertBefore(info.velement_dom, ref.dom);
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
                    .text => {
                        return error.CannotMoveInTextNode;
                    },
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

    var new_velement = try createVElementFromComponent(allocator, new_component);
    defer new_velement.deinit(allocator);

    try diff(allocator, &self.vtree, &new_velement, null, &patches);

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

const zx = @import("../root.zig");
const std = @import("std");
const Document = zx.Client.bom.Document;
