const std = @import("std");
const data = @import("data.zig");
const string = @import("string.zig");

const Component = data.Component;
const StateItem = data.StateItem;

pub fn findComponentById(comps: []const Component, id: []const u8) ?Component {
    for (comps) |comp| {
        if (std.mem.eql(u8, comp.id, id)) return comp;
        if (comp.has_children) {
            if (findComponentById(comp.children, id)) |found| return found;
        }
    }
    return null;
}

pub fn filterNativeElements(allocator: std.mem.Allocator, comps: []const Component) []const Component {
    if (data.show_native_elements) return comps;
    var list = std.ArrayList(Component).empty;
    for (comps) |comp| {
        if (comp.is_native) {
            const promoted = filterNativeElements(allocator, comp.children);
            list.appendSlice(allocator, promoted) catch {};
        } else {
            var filtered = comp;
            filtered.children = filterNativeElements(allocator, comp.children);
            filtered.has_children = filtered.children.len > 0;
            list.append(allocator, filtered) catch {};
        }
    }
    return list.toOwnedSlice(allocator) catch comps;
}

pub fn getComponentGroupClass(
    name: []const u8,
    has_children: bool,
    children: []const Component,
    search: []const u8,
) []const u8 {
    if (componentOrDescendantMatches(name, has_children, children, search)) return "component-group";
    return "component-group component-group-hidden";
}

pub fn getStateItemGroupClass(item: StateItem, filter: []const u8) []const u8 {
    if (stateItemOrDescendantMatches(item, filter)) return "state-item-group";
    return "state-item-group state-item-group-hidden";
}

fn stateItemOrDescendantMatches(item: StateItem, filter: []const u8) bool {
    if (filter.len == 0) return true;
    if (string.containsIgnoreCase(item.key, filter)) return true;
    if (string.containsIgnoreCase(item.value, filter)) return true;
    if (item.meta.len > 0 and string.containsIgnoreCase(item.meta, filter)) return true;
    for (item.children) |child| {
        if (stateItemOrDescendantMatches(child, filter)) return true;
    }
    return false;
}

fn componentOrDescendantMatches(
    name: []const u8,
    has_children: bool,
    children: []const Component,
    search: []const u8,
) bool {
    if (search.len == 0) return true;
    if (string.containsIgnoreCase(name, search)) return true;
    if (has_children) {
        for (children) |child| {
            if (componentOrDescendantMatches(child.name, child.has_children, child.children, search)) return true;
        }
    }
    return false;
}
