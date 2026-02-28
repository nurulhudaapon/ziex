const std = @import("std");
const zx = @import("root.zig");

const Allocator = std.mem.Allocator;

pub fn isSignalType(comptime T: type) bool {
    const ti = @typeInfo(T);
    if (ti == .pointer) {
        const Child = ti.pointer.child;
        if (@typeInfo(Child) == .@"struct") {
            return @hasField(Child, "id") and
                @hasField(Child, "value") and
                @hasDecl(Child, "get") and
                @hasDecl(Child, "set") and
                @hasDecl(Child, "notifyChange");
        }
    }
    return false;
}

pub fn isComputedType(comptime T: type) bool {
    const ti = @typeInfo(T);
    if (ti == .pointer) {
        const Child = ti.pointer.child;
        if (@typeInfo(Child) == .@"struct") {
            return @hasField(Child, "id") and
                @hasDecl(Child, "get") and
                !@hasDecl(Child, "set");
        }
    }
    return false;
}

pub fn toStateItems(allocator: Allocator, comptime T: type, value: T) anyerror![]const ComponentSerializable.StateItem {
    const ti = @typeInfo(T);
    if (ti != .@"struct") return &[_]ComponentSerializable.StateItem{};

    const fields = ti.@"struct".fields;
    var items = try allocator.alloc(ComponentSerializable.StateItem, fields.len);
    inline for (fields, 0..) |field, i| {
        items[i] = try toStateItem(allocator, field.type, field.name, @field(value, field.name), 0);
    }
    return items;
}

pub fn toStateItem(allocator: Allocator, comptime T: type, key: []const u8, value: T, depth: usize) anyerror!ComponentSerializable.StateItem {
    var item: ComponentSerializable.StateItem = .{
        .key = key,
        .value = "",
        .meta = "",
        .children = &[_]ComponentSerializable.StateItem{},
    };

    if (depth > 6) {
        item.value = "...";
        return item;
    }

    if (comptime isSignalType(T)) {
        item.meta = "(Ref)";
        // For signals, we show the value of the signal
        const val = value.get();
        const ValueT = @TypeOf(val);
        const sub = try toStateItem(allocator, ValueT, key, val, depth + 1);
        item.value = sub.value;
        item.children = sub.children;
        return item;
    }

    if (comptime isComputedType(T)) {
        item.meta = "(Computed)";
        // For computed, we show the value
        const val = value.get();
        const ValueT = @TypeOf(val);
        const sub = try toStateItem(allocator, ValueT, key, val, depth + 1);
        item.value = sub.value;
        item.children = sub.children;
        return item;
    }

    const ti = @typeInfo(T);
    switch (ti) {
        .@"struct" => |s| {
            item.value = "Object";
            var children = try allocator.alloc(ComponentSerializable.StateItem, s.fields.len);
            inline for (s.fields, 0..) |field, i| {
                children[i] = try toStateItem(allocator, field.type, field.name, @field(value, field.name), depth + 1);
            }
            item.children = children;
        },
        .pointer => |p| {
            if (p.size == .slice and p.child == u8) {
                item.value = try std.json.Stringify.valueAlloc(allocator, value, .{});
            } else if (p.size == .slice) {
                item.value = "Array";
                var children = try allocator.alloc(ComponentSerializable.StateItem, value.len);
                for (value, 0..) |v, i| {
                    var buf: [32]u8 = undefined;
                    const index_key = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "item";
                    children[i] = try toStateItem(allocator, p.child, try allocator.dupe(u8, index_key), v, depth + 1);
                }
                item.children = children;
            } else {
                item.value = "Pointer";
            }
        },
        .optional => |opt| {
            if (value) |v| {
                return try toStateItem(allocator, opt.child, key, v, depth);
            } else {
                item.value = "null";
            }
        },
        .int, .float, .bool => {
            item.value = try std.json.Stringify.valueAlloc(allocator, value, .{});
        },
        .@"fn" => {
            item.value = "fn()";
        },
        .error_union => {
            if (value) |v| {
                return try toStateItem(allocator, @TypeOf(v), key, v, depth);
            } else |err| {
                item.value = @errorName(err);
            }
        },
        else => {
            item.value = @typeName(T);
        },
    }

    return item;
}

pub const ComponentSerializable = struct {
    pub const StateItem = struct {
        key: []const u8,
        value: []const u8,
        meta: []const u8 = "",
        children: []const StateItem = &[_]StateItem{},
    };

    /// Serializable attribute (excludes handler which is a function pointer)
    const AttributeSerializable = struct {
        name: []const u8,
        value: ?[]const u8 = null,
    };

    tag: ?zx.ElementTag = null,
    component: ?[]const u8 = null,
    text: ?[]const u8 = null,
    props: ?[]const StateItem = null,
    attributes: ?[]const AttributeSerializable = null,
    children: ?[]ComponentSerializable = null,

    /// Convert Element.Attribute slice to serializable form (strips handlers)
    fn serializeAttributes(allocator: Allocator, attrs: ?[]const zx.Element.Attribute) !?[]const AttributeSerializable {
        const attributes = attrs orelse return null;
        const serializable = try allocator.alloc(AttributeSerializable, attributes.len);
        for (attributes, 0..) |attr, i| {
            serializable[i] = .{
                .name = attr.name,
                .value = attr.value,
                // handler is intentionally excluded - not serializable
            };
        }
        return serializable;
    }

    fn serializeProps(allocator: Allocator, getStateItems: ?*const fn (Allocator, *const anyopaque) anyerror![]const StateItem, props_ptr: ?*const anyopaque) !?[]const StateItem {
        const gsi = getStateItems orelse return null;
        const pp = props_ptr orelse return null;

        return try gsi(allocator, pp);
    }

    pub fn init(allocator: Allocator, component: zx.Component, options: zx.Component.SerializeOptions) anyerror!ComponentSerializable {
        return switch (component) {
            .none => .{},
            .text => |text| .{ .text = text },
            .signal_text => |sig| .{ .text = sig.current_text },
            .element => |element| blk: {
                const children_serializable = if (element.children) |children| blk2: {
                    break :blk2 try ComponentSerializable.initChildren(allocator, children, options);
                } else null;
                break :blk .{
                    .tag = element.tag,
                    .attributes = if (options.include_attributes) try serializeAttributes(allocator, element.attributes) else null,
                    .children = children_serializable,
                };
            },
            .component_csr => |component_csr| blk: {
                const children_serializable = if (component_csr.children) |children| blk2: {
                    const serializable = try allocator.alloc(ComponentSerializable, 1);
                    serializable[0] = try ComponentSerializable.init(allocator, children.*, options);
                    break :blk2 serializable;
                } else null;
                break :blk .{
                    .component = component_csr.name,
                    .props = if (options.include_props) try serializeProps(allocator, component_csr.getStateItems, component_csr.props_ptr) else null,
                    .children = children_serializable,
                };
            },
            .component_fn => |comp_fn| blk: {
                // Resolve component_fn by calling it, then serialize the result
                // This avoids serializing anyopaque fields
                const resolved = try comp_fn.call();

                const resolved_serializable = try ComponentSerializable.init(allocator, resolved, options);
                const children_slice = try allocator.alloc(ComponentSerializable, 1);
                children_slice[0] = resolved_serializable;
                break :blk .{
                    .component = comp_fn.name,
                    .props = if (options.include_props) try serializeProps(allocator, comp_fn.getStateItems, comp_fn.propsPtr) else null,
                    .children = children_slice,
                };
            },
        };
    }

    pub fn initChildren(allocator: Allocator, children: []const zx.Component, options: zx.Component.SerializeOptions) anyerror![]ComponentSerializable {
        if (!options.only_components) {
            const children_serializable = try allocator.alloc(ComponentSerializable, children.len);
            for (children, 0..) |child, i| {
                children_serializable[i] = try ComponentSerializable.init(allocator, child, options);
            }
            return children_serializable;
        }

        var list = std.ArrayList(ComponentSerializable).empty;
        for (children) |child| {
            switch (child) {
                .element => |elem| {
                    if (elem.children) |child_elements| {
                        const sub = try initChildren(allocator, child_elements, options);
                        try list.appendSlice(allocator, sub);
                    }
                },
                .component_fn, .component_csr => {
                    try list.append(allocator, try ComponentSerializable.init(allocator, child, options));
                },
                else => {}, // Skip text, none, etc.
            }
        }
        return list.toOwnedSlice(allocator);
    }

    pub fn serialize(self: ComponentSerializable, writer: *std.Io.Writer) !void {
        try zx.prop.serialize(ComponentSerializable, self, writer);
    }
};
