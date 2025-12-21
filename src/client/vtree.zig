pub const VDOMTree = @This();

/// Virtual DOM element that holds both the component and its corresponding DOM element reference
pub const VElement = struct {
    /// The actual DOM node (element or text)
    dom: Document.HTMLNode,
    component: zx.Component,
    children: std.ArrayList(VElement),

    fn createFromComponent(
        allocator: zx.Allocator,
        document: Document,
        parent_dom: ?Document.HTMLElement,
        component: zx.Component,
    ) !VElement {
        switch (component) {
            .element => |element| {
                const dom_element = document.createElement(@tagName(element.tag));

                if (element.attributes) |attributes| {
                    for (attributes) |attr| {
                        const attr_val = if (attr.value) |val| val else "true";
                        dom_element.setAttribute(attr.name, attr_val);
                    }
                }

                var velement = VElement{
                    .dom = .{ .element = dom_element },
                    .component = component,
                    .children = std.ArrayList(VElement).empty,
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

                const velement = VElement{
                    .dom = .{ .text = text_node },
                    .component = component,
                    .children = std.ArrayList(VElement).empty,
                };

                if (parent_dom) |parent| {
                    try parent.appendChild(velement.dom);
                }

                return velement;
            },
            .component_fn => |comp_fn| {
                const resolved = comp_fn.callFn(comp_fn.propsPtr, allocator);
                return try createFromComponent(allocator, document, parent_dom, resolved);
            },
            .component_csr => |component_csr| {
                const dom_element = document.createElement("div");
                dom_element.setAttribute("id", component_csr.id);
                dom_element.setAttribute("data-name", component_csr.name);
                dom_element.setAttribute("data-props", component_csr.props_json orelse "{}");

                const velement = VElement{
                    .dom = .{ .element = dom_element },
                    .component = component,
                    .children = std.ArrayList(VElement).empty,
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

/// Patch types following React's reconciliation algorithm
/// These match React Fiber's effect tags
pub const PatchType = enum {
    /// Update properties/attributes of an existing node
    UPDATE,
    /// Insert a new node (placement)
    PLACEMENT,
    /// Remove a node (deletion)
    DELETION,
    /// Replace an entire node
    REPLACE,
};

/// Patch data structure following React's architecture
pub const PatchData = union(PatchType) {
    /// UPDATE: Update attributes/properties
    UPDATE: struct {
        /// The VElement to update
        velement: *VElement,
        /// Attributes to update (name -> value mapping)
        attributes: std.StringHashMap([]const u8),
        /// Attributes to remove
        removed_attributes: std.ArrayList([]const u8),
    },
    /// PLACEMENT: Insert a new node
    PLACEMENT: struct {
        /// The new VElement to insert
        velement: VElement,
        /// Parent VElement where to insert
        parent: *VElement,
        /// Reference node (for insertBefore), null for appendChild
        reference: ?*VElement,
    },
    /// DELETION: Remove a node
    DELETION: struct {
        /// The VElement to remove
        velement: *VElement,
        /// Parent VElement
        parent: *VElement,
    },
    /// REPLACE: Replace an entire node
    REPLACE: struct {
        /// The old VElement to replace
        old_velement: *VElement,
        /// The new VElement
        new_velement: VElement,
        /// Parent VElement
        parent: *VElement,
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

/// Initialize a VDOMTree from a root component
/// This creates the entire virtual DOM tree with actual DOM element references
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
    // const console = Console.init();

    // Component
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

    // Attributes
    switch (new_velement.component) {
        .element => |new_element| {
            switch (old_velement.component) {
                .element => |old_element| {
                    // console.str("diffAttributes");

                    // if (new_element.attributes) |attrs|
                    //     for (attrs) |attr|
                    //         console.str(attr.name);

                    var attributes_to_update = std.StringHashMap([]const u8).init(allocator);
                    var attributes_to_remove = std.ArrayList([]const u8).empty;

                    // Remove missing attributes
                    if (old_element.attributes) |old_attrs| {
                        for (old_attrs) |old_attr| {
                            var found = false;
                            if (new_element.attributes) |new_attrs| {
                                for (new_attrs) |new_attr| {
                                    if (std.mem.eql(u8, old_attr.name, new_attr.name)) {
                                        found = true;
                                        // Value changed
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

                    // Add new attributes
                    if (new_element.attributes) |new_attrs| {
                        for (new_attrs) |new_attr| {
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

                    // Children
                    try diffChildren(allocator, old_velement, new_velement, old_velement, patches);
                },
                else => {},
            }
        },
        .text => |new_text| {
            switch (old_velement.component) {
                .text => |old_text| {
                    const console = Console.init();
                    const log_text = std.fmt.allocPrint(allocator, "diffText: Old: {s}, New: {s}", .{ old_text, new_text }) catch @panic("OOM");
                    defer allocator.free(log_text);
                    console.str(log_text);

                    if (!std.mem.eql(u8, old_text, new_text)) {
                        switch (old_velement.dom) {
                            .text => |text_node| {
                                text_node.setNodeValue(if (new_text.len > 0) new_text else "");
                            },
                            else => {},
                        }
                        // Update the component to reflect the new text value
                        old_velement.component = .{ .text = new_text };
                    }
                },
                else => {},
            }
        },
        else => {},
    }
}

fn diffChildren(
    allocator: zx.Allocator,
    old_velement: *VElement,
    new_velement: *const VElement,
    parent: *VElement,
    patches: *std.ArrayList(Patch),
) !void {
    const console = Console.init();

    const old_children = old_velement.children.items;
    const new_children = if (new_velement.component == .element) blk: {
        const element = new_velement.component.element;
        if (element.children) |children| {
            break :blk children;
        } else {
            break :blk &[_]zx.Component{};
        }
    } else &[_]zx.Component{};

    var old_index: usize = 0;
    var new_index: usize = 0;

    if (old_velement.component.element.tag == .div)
        console.str(std.fmt.allocPrint(allocator, "Child ({s}) Len: Old: {d}, New: {d} | Index: Old: {d}, New: {d}", .{ @tagName(old_velement.component.element.tag), old_children.len, new_children.len, old_index, new_index }) catch @panic("OOM"));

    while (old_index < old_children.len and new_index < new_children.len) {
        const old_child_velement = &old_velement.children.items[old_index];
        const new_child_component = new_children[new_index];

        var new_child_velement = try createVElementFromComponent(allocator, new_child_component);
        defer new_child_velement.deinit(allocator);

        try diff(allocator, old_child_velement, &new_child_velement, parent, patches);

        old_index += 1;
        new_index += 1;
    }

    while (old_index < old_children.len) {
        const old_child = &old_velement.children.items[old_index];
        try patches.append(allocator, Patch{
            .type = .DELETION,
            .data = .{
                .DELETION = .{
                    .velement = old_child,
                    .parent = parent,
                },
            },
        });
        old_index += 1;
    }

    while (new_index < new_children.len) {
        const new_child_component = new_children[new_index];
        const new_child_velement = try createVElementFromComponent(allocator, new_child_component);
        try patches.append(allocator, Patch{
            .type = .PLACEMENT,
            .data = .{
                .PLACEMENT = .{
                    .velement = new_child_velement,
                    .parent = parent,
                    .reference = null,
                },
            },
        });
        new_index += 1;
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
    return try VElement.createFromComponent(allocator, document, null, velement.component);
}

fn createVElementFromComponent(allocator: zx.Allocator, component: zx.Component) !VElement {
    const document = Document.init(allocator);
    return try VElement.createFromComponent(allocator, document, null, component);
}

/// Compare two HTMLNode values to check if they refer to the same DOM node
/// Workaround for zig_js boolean return bug: use a function that returns a number
fn areNodesEqual(node1: Document.HTMLNode, node2: Document.HTMLNode) bool {
    const ref1 = switch (node1) {
        .element => |elem| elem.ref,
        .text => |text| text.ref,
    };
    const ref2 = switch (node2) {
        .element => |elem| elem.ref,
        .text => |text| text.ref,
    };
    // Use JavaScript's === operator via a helper function that returns a number
    // to avoid the zig_js boolean return type bug
    const compare_fn = js.global.call(js.Object, "eval", .{js.string("(function(a, b) { return a === b ? 1 : 0; })")}) catch return false;
    const result = compare_fn.call(f64, "call", .{ js.global, ref1, ref2 }) catch return false;
    return result == 1;
}

pub fn applyPatches(
    allocator: zx.Allocator,
    patches: std.ArrayList(Patch),
) !void {
    for (patches.items) |patch| {
        switch (patch.type) {
            .UPDATE => {
                const update_data = patch.data.UPDATE;
                const velement = update_data.velement;

                switch (velement.dom) {
                    .element => |element| {
                        // Update attributes
                        var attr_iter = update_data.attributes.iterator();
                        while (attr_iter.next()) |entry| {
                            element.setAttribute(entry.key_ptr.*, entry.value_ptr.*);
                        }

                        // Remove attributes
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

                        try parent.children.append(allocator, new_child);
                    },
                    .text => {
                        return error.CannotAppendToTextNode;
                    },
                }
            },
            .DELETION => {
                const deletion_data = patch.data.DELETION;
                const velement = deletion_data.velement;
                const parent = deletion_data.parent;

                switch (parent.dom) {
                    .element => |parent_element| {
                        try parent_element.removeChild(velement.dom);

                        // Remove from parent's children list
                        const children = &parent.children;
                        for (children.items, 0..) |child, i| {
                            if (areNodesEqual(child.dom, velement.dom)) {
                                _ = children.swapRemove(i);
                                break;
                            }
                        }

                        velement.deinit(allocator);
                    },
                    .text => {
                        return error.CannotRemoveFromTextNode;
                    },
                }
            },
            .REPLACE => {
                const replace_data = patch.data.REPLACE;
                const old_velement = replace_data.old_velement;
                const new_velement = replace_data.new_velement;
                const parent = replace_data.parent;

                switch (parent.dom) {
                    .element => |parent_element| {
                        try parent_element.replaceChild(new_velement.dom, old_velement.dom);

                        // Replace in parent's children list
                        const children = &parent.children;
                        for (children.items, 0..) |*child, i| {
                            if (areNodesEqual(child.dom, old_velement.dom)) {
                                children.items[i] = new_velement;
                                break;
                            }
                        }

                        old_velement.deinit(allocator);
                    },
                    .text => {
                        return error.CannotReplaceInTextNode;
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

/// Update the VElement tree's components to match a new component tree
/// This is called after applying patches to keep the VElement tree in sync
fn updateVElementComponent(velement: *VElement, new_component: zx.Component) void {
    velement.component = new_component;

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

/// Update the VDOMTree's components to match a new component
/// This should be called after applying patches to keep the tree in sync
pub fn updateComponents(self: *VDOMTree, new_component: zx.Component) void {
    updateVElementComponent(&self.vtree, new_component);
}

const zx = @import("../root.zig");
const std = @import("std");
const Document = zx.Client.bom.Document;
const Console = zx.Client.bom.Console;
const js = @import("js");
