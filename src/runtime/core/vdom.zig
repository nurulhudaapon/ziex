pub const VDOMTree = @This();

var next_velement_id: u64 = 0;

pub const VNode = struct {
    id: u64,
    component: zx.Component,
    children: std.ArrayListUnmanaged(*VNode),
    key: ?[]const u8 = null,
    owner_component_id: []const u8 = "",

    pub const Id = u64;

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
                return comp_fn.key;
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
        component: zx.Component,
        owner_component_id: []const u8,
        sibling_index: usize,
    ) anyerror!*VNode {
        const self = try allocator.create(VNode);
        errdefer allocator.destroy(self);

        self.* = VNode{
            .id = nextId(),
            .component = component,
            .children = .empty,
            .key = null,
            .owner_component_id = owner_component_id,
        };

        switch (component) {
            .none => {},
            .element => |element| {
                if (element.attributes) |attributes| {
                    for (attributes) |attr| {
                        if (std.mem.eql(u8, attr.name, "key")) {
                            self.key = attr.value;
                            break;
                        }
                    }
                }

                if (element.children) |children| {
                    // Flatten fragments: lift fragment children into this node's
                    // children list (React-style — fragments produce no DOM node).
                    const flat = try flattenComponents(allocator, children);
                    try self.children.ensureTotalCapacity(allocator, flat.len);
                    for (flat, 0..) |child, child_index| {
                        const child_vnode = try createFromComponent(allocator, child, owner_component_id, child_index);
                        self.children.appendAssumeCapacity(child_vnode);
                    }
                }
            },
            .text => |text| {
                _ = text;
            },
            .component_fn => |_| {
                const next_owner_component_id = componentOwnerId(allocator, component, owner_component_id, sibling_index);
                const resolved = try resolveComponent(allocator, component, owner_component_id, sibling_index);
                allocator.destroy(self);
                return try createFromComponent(allocator, resolved, next_owner_component_id, 0);
            },
            .component_csr => |component_csr| {
                _ = component_csr;
            },
        }
        return self;
    }

    pub fn deinit(self: *VNode, allocator: zx.Allocator) void {
        for (self.children.items) |child| {
            child.deinit(allocator);
        }
        self.children.deinit(allocator);
        allocator.destroy(self);
    }
};

pub const VElement = VNode;

pub const PatchType = enum {
    UPDATE,
    PLACEMENT,
    DELETION,
    REPLACE,
    MOVE,
    TEXT,
};

pub const PatchData = union(PatchType) {
    UPDATE: struct {
        vnode_id: u64,
        attributes: std.StringHashMap([]const u8),
        removed_attributes: std.ArrayList([]const u8),
    },
    PLACEMENT: struct {
        vnode: *VNode,
        parent_id: u64,
        reference_id: ?u64,
        index: usize,
    },
    DELETION: struct {
        vnode_id: u64,
        parent_id: u64,
    },
    REPLACE: struct {
        old_vnode_id: u64,
        new_vnode: *VNode,
        parent_id: u64,
    },
    MOVE: struct {
        vnode_id: u64,
        parent_id: u64,
        reference_id: ?u64,
        new_index: usize,
    },
    TEXT: struct {
        vnode_id: u64,
        new_text: []const u8,
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

vtree: *VNode,

pub var current_component_owner: []const u8 = "";

pub fn init(allocator: zx.Allocator, component: zx.Component) VDOMTree {
    const root_vnode = VNode.createFromComponent(allocator, component, current_component_owner, 0) catch @panic("Error creating root VNode");
    return VDOMTree{ .vtree = root_vnode };
}

pub fn diff(
    allocator: zx.Allocator,
    old_vnode: *VNode,
    new_component: zx.Component,
    parent: ?*VNode,
    patches: *std.ArrayList(Patch),
) anyerror!void {
    if (old_vnode.component == .component_fn and new_component == .component_fn) {
        if (old_vnode.component.component_fn.propsPtr == new_component.component_fn.propsPtr) {
            return;
        }
    }

    const resolved_component = try resolveComponent(allocator, new_component, old_vnode.owner_component_id, 0);

    if (!areComponentsSameType(old_vnode.component, resolved_component)) {
        if (parent) |p| {
            try patches.append(allocator, Patch{
                .type = .REPLACE,
                .data = .{
                    .REPLACE = .{
                        .old_vnode_id = old_vnode.id,
                        .new_vnode = try createVNodeFromComponent(allocator, resolved_component, old_vnode.owner_component_id),
                        .parent_id = p.id,
                    },
                },
            });
        }
        return;
    }

    switch (resolved_component) {
        .element => |new_element| {
            switch (old_vnode.component) {
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
                                    .vnode_id = old_vnode.id,
                                    .attributes = attributes_to_update,
                                    .removed_attributes = attributes_to_remove,
                                },
                            },
                        });
                    }

                    old_vnode.component = resolved_component;
                    old_vnode.key = VNode.extractKey(resolved_component);

                    try reconcileChildren(allocator, old_vnode, resolved_component, old_vnode, patches);
                },
                else => {},
            }
        },
        .text => |new_text| {
            switch (old_vnode.component) {
                .text => |old_text| {
                    if (!std.mem.eql(u8, old_text, new_text)) {
                        try patches.append(allocator, Patch{
                            .type = .TEXT,
                            .data = .{
                                .TEXT = .{
                                    .vnode_id = old_vnode.id,
                                    .new_text = new_text,
                                },
                            },
                        });
                        old_vnode.component = .{ .text = new_text };
                    }
                },
                else => {},
            }
        },
        else => {},
    }
}

pub fn areComponentsSameType(old: zx.Component, new: zx.Component) bool {
    switch (old) {
        .none => return new == .none,
        .element => |old_elem| switch (new) {
            .element => |new_elem| return old_elem.tag == new_elem.tag,
            else => return false,
        },
        .text => switch (new) {
            .text => return true,
            else => return false,
        },
        .component_fn => switch (new) {
            .component_fn => return true,
            else => return false,
        },
        .component_csr => switch (new) {
            .component_csr => return true,
            else => return false,
        },
    }
}

pub fn diffWithComponent(
    self: *VDOMTree,
    allocator: zx.Allocator,
    new_component: zx.Component,
) !std.ArrayList(Patch) {
    var patches = std.ArrayList(Patch).empty;
    try diff(allocator, self.vtree, new_component, null, &patches);
    return patches;
}

pub fn deinit(self: *VDOMTree, allocator: zx.Allocator) void {
    self.vtree.deinit(allocator);
}

pub fn resolveComponent(allocator: zx.Allocator, component: zx.Component, owner_component_id: []const u8, sibling_index: usize) !zx.Component {
    var curr = component;
    while (true) {
        switch (curr) {
            .component_fn => |comp_fn| {
                const component_id = componentOwnerId(allocator, curr, owner_component_id, sibling_index);
                comp_fn.setIdentity(component_id, @truncate(next_velement_id));
                curr = try comp_fn.call();
            },
            else => return curr,
        }
    }
}

fn createVNodeFromComponent(allocator: zx.Allocator, component: zx.Component, owner_component_id: []const u8) anyerror!*VNode {
    return try VNode.createFromComponent(allocator, component, owner_component_id, 0);
}

fn flattenComponents(allocator: zx.Allocator, children: []const zx.Component) ![]const zx.Component {
    var has_fragments = false;
    for (children) |child| {
        switch (child) {
            .element => |elem| {
                if (elem.tag == .fragment) {
                    has_fragments = true;
                    break;
                }
            },
            else => {},
        }
    }
    if (!has_fragments) return children;

    const count = countFlattened(children);
    const result = try allocator.alloc(zx.Component, count);
    var idx: usize = 0;
    flattenInto(children, result, &idx);
    return result;
}

fn countFlattened(children: []const zx.Component) usize {
    var count: usize = 0;
    for (children) |child| {
        switch (child) {
            .element => |elem| {
                if (elem.tag == .fragment) {
                    count += if (elem.children) |fc| countFlattened(fc) else 0;
                    continue;
                }
            },
            else => {},
        }
        count += 1;
    }
    return count;
}

fn flattenInto(children: []const zx.Component, result: []zx.Component, idx: *usize) void {
    for (children) |child| {
        switch (child) {
            .element => |elem| {
                if (elem.tag == .fragment) {
                    if (elem.children) |fc| flattenInto(fc, result, idx);
                    continue;
                }
            },
            else => {},
        }
        result[idx.*] = child;
        idx.* += 1;
    }
}

/// Reconcile children of a parent vnode. Mirrors React's reconcileChildrenArray.
///
/// React's algorithm (from ReactChildFiber.js):
///   Pass 1: advance through old+new in lockstep while keys match.
///             Stops on first key mismatch (not type mismatch).
///             Same key + different type → delete old, insert new in-place (REPLACE).
///   Exit early if new or old children are exhausted after pass 1.
///   Pass 2: build key→old-index map (keyless children use their
///             absolute index as implicit key, per mapRemainingChildren).
///             Iterate remaining new children; for each, look up old by key/index.
///             Track reuse positions with lastPlacedIndex (placeChild logic):
///               reused node whose old_index < lastPlacedIndex → MOVE.
///               reused node whose old_index >= lastPlacedIndex → stays, update tracker.
///               no match → PLACEMENT.
///             Delete every old child not reused.
///   Backward pass (our addition for reference_id) — emit PLACEMENT/MOVE patches
///             back-to-front so each patch's reference_id points to an already-resolved node.
fn reconcileChildren(
    allocator: zx.Allocator,
    old_velement: *VElement,
    new_component: zx.Component,
    parent: *VElement,
    patches: *std.ArrayList(Patch),
) !void {
    const old_children = old_velement.children.items;
    const new_children_raw: []const zx.Component = if (new_component == .element) blk: {
        const element = new_component.element;
        if (element.children) |children| break :blk children else break :blk &[_]zx.Component{};
    } else &[_]zx.Component{};
    const new_children_slice = try flattenComponents(allocator, new_children_raw);

    var old_idx: usize = 0;
    var new_idx: usize = 0;
    var last_placed_index: usize = 0;

    // Pass 1: sync prefix while keys match
    while (old_idx < old_children.len and new_idx < new_children_slice.len) {
        const old_child = old_children[old_idx];
        const resolved = try resolveComponent(allocator, new_children_slice[new_idx], old_velement.owner_component_id, new_idx);

        if (!old_child.keysMatch(resolved)) break;

        if (areComponentsSameType(old_child.component, resolved)) {
            try diff(allocator, old_child, resolved, parent, patches);
            last_placed_index = old_idx;
        } else {
            try patches.append(allocator, Patch{
                .type = .REPLACE,
                .data = .{ .REPLACE = .{
                    .old_vnode_id = old_child.id,
                    .new_vnode = try createVNodeFromComponent(allocator, resolved, componentOwnerId(allocator, new_children_slice[new_idx], old_velement.owner_component_id, new_idx)),
                    .parent_id = parent.id,
                } },
            });
        }

        old_idx += 1;
        new_idx += 1;
    }

    // New children exhausted → delete remaining old
    if (new_idx >= new_children_slice.len) {
        while (old_idx < old_children.len) : (old_idx += 1) {
            try patches.append(allocator, Patch{
                .type = .DELETION,
                .data = .{ .DELETION = .{
                    .vnode_id = old_children[old_idx].id,
                    .parent_id = parent.id,
                } },
            });
        }
        return;
    }

    // Old children exhausted → insert remaining new
    if (old_idx >= old_children.len) {
        while (new_idx < new_children_slice.len) : (new_idx += 1) {
            const resolved = try resolveComponent(allocator, new_children_slice[new_idx], old_velement.owner_component_id, new_idx);
            const new_vnode = try createVNodeFromComponent(allocator, resolved, componentOwnerId(allocator, new_children_slice[new_idx], old_velement.owner_component_id, new_idx));
            try patches.append(allocator, Patch{
                .type = .PLACEMENT,
                .data = .{ .PLACEMENT = .{
                    .vnode = new_vnode,
                    .parent_id = parent.id,
                    .reference_id = null,
                    .index = new_idx,
                } },
            });
        }
        return;
    }

    // Map remaining old children
    var key_map = std.StringHashMap(usize).init(allocator);
    defer key_map.deinit();
    var index_map = std.AutoHashMap(usize, usize).init(allocator);
    defer index_map.deinit();

    for (old_children[old_idx..], old_idx..) |old_child, oi| {
        if (old_child.key) |k| {
            try key_map.put(k, oi);
        } else {
            try index_map.put(oi, oi);
        }
    }

    const remaining_new = new_children_slice[new_idx..];
    const remaining_cnt = remaining_new.len;

    // Per-slot decision: source[i] = -1 (new), or >= 0 (matched old abs index).
    var source = try allocator.alloc(isize, remaining_cnt);
    defer allocator.free(source);
    @memset(source, -1);

    var needs_move = try allocator.alloc(bool, remaining_cnt);
    defer allocator.free(needs_move);
    @memset(needs_move, false);

    // Pre-created VNodes for insertions (source[i] == -1).
    var new_vnodes = try allocator.alloc(?*VNode, remaining_cnt);
    defer allocator.free(new_vnodes);
    @memset(new_vnodes, null);

    var used_old = try allocator.alloc(bool, old_children.len - old_idx);
    defer allocator.free(used_old);
    @memset(used_old, false);

    for (remaining_new, 0..) |nc, ni| {
        const abs_new_idx = new_idx + ni;
        const resolved = try resolveComponent(allocator, nc, old_velement.owner_component_id, abs_new_idx);
        const new_key = VElement.extractKey(resolved);

        const found_oi: ?usize = if (new_key) |k| key_map.get(k) else index_map.get(abs_new_idx);

        if (found_oi) |oi| {
            const old_child = old_children[oi];
            if (areComponentsSameType(old_child.component, resolved)) {
                try diff(allocator, old_child, resolved, parent, patches);
                source[ni] = @intCast(oi);
                used_old[oi - old_idx] = true;
                if (oi < last_placed_index) {
                    needs_move[ni] = true;
                } else {
                    last_placed_index = oi;
                }
            } else {
                used_old[oi - old_idx] = true;
                try patches.append(allocator, Patch{
                    .type = .DELETION,
                    .data = .{ .DELETION = .{ .vnode_id = old_child.id, .parent_id = parent.id } },
                });
                new_vnodes[ni] = try createVNodeFromComponent(allocator, resolved, componentOwnerId(allocator, nc, old_velement.owner_component_id, abs_new_idx));
            }
        } else {
            new_vnodes[ni] = try createVNodeFromComponent(allocator, resolved, componentOwnerId(allocator, nc, old_velement.owner_component_id, abs_new_idx));
        }
    }

    // Delete unused old children
    for (used_old, 0..) |used, offset| {
        if (!used) {
            try patches.append(allocator, Patch{
                .type = .DELETION,
                .data = .{ .DELETION = .{
                    .vnode_id = old_children[old_idx + offset].id,
                    .parent_id = parent.id,
                } },
            });
        }
    }

    // Backward pass: emit PLACEMENT/MOVE with correct reference_ids
    var last_ref_id: ?u64 = null;
    var k: usize = remaining_cnt;
    while (k > 0) {
        k -= 1;
        if (source[k] == -1) {
            const new_vnode = new_vnodes[k].?;
            try patches.append(allocator, Patch{
                .type = .PLACEMENT,
                .data = .{ .PLACEMENT = .{
                    .vnode = new_vnode,
                    .parent_id = parent.id,
                    .reference_id = last_ref_id,
                    .index = new_idx + k,
                } },
            });
            last_ref_id = new_vnode.id;
        } else if (needs_move[k]) {
            const oi: usize = @intCast(source[k]);
            try patches.append(allocator, Patch{
                .type = .MOVE,
                .data = .{ .MOVE = .{
                    .vnode_id = old_children[oi].id,
                    .parent_id = parent.id,
                    .reference_id = last_ref_id,
                    .new_index = new_idx + k,
                } },
            });
            last_ref_id = old_children[oi].id;
        } else {
            const oi: usize = @intCast(source[k]);
            last_ref_id = old_children[oi].id;
        }
    }
}

fn componentOwnerId(allocator: zx.Allocator, component: zx.Component, owner_component_id: []const u8, sibling_index: usize) []const u8 {
    return switch (component) {
        .component_fn => |comp_fn| blk: {
            const suffix = comp_fn.key orelse std.fmt.allocPrint(allocator, "#{d}", .{sibling_index}) catch break :blk owner_component_id;
            break :blk std.fmt.allocPrint(allocator, "{s}/{s}:{s}", .{
                owner_component_id,
                comp_fn.name,
                suffix,
            }) catch owner_component_id;
        },
        else => owner_component_id,
    };
}

const zx = @import("../../root.zig");
const std = @import("std");
