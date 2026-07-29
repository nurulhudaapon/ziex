const std = @import("std");
const builtin = @import("builtin");
const zx = @import("../root.zig");

const Allocator = std.mem.Allocator;

pub const SerializeOptions = struct {
    only_components: bool = true,
    include_attributes: bool = true,
    include_props: bool = true,
};

pub fn format(component: zx.Component, w: *std.Io.Writer) error{WriteFailed}!void {
    formatWithOptions(component, w, .{}) catch return error.WriteFailed;
}

pub fn formatWithOptions(component: zx.Component, w: *std.Io.Writer, options: SerializeOptions) anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var serializable = try ComponentSerializable.init(allocator, component, options);
    try serializable.serialize(w);
}

pub const ComponentSerializable = struct {
    pub const StateItem = struct {
        key: []const u8,
        value: []const u8,
        meta: []const u8 = "",
        children: []const StateItem = &[_]StateItem{},
    };

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

    pub fn toStateItems(allocator: Allocator, comptime T: type, value: T) anyerror![]const StateItem {
        const ti = @typeInfo(T);
        if (ti != .@"struct") return &[_]StateItem{};

        const field_names = ti.@"struct".field_names;
        const field_types = ti.@"struct".field_types;
        var items = try allocator.alloc(StateItem, field_names.len);
        inline for (field_names, 0..) |name, i| {
            items[i] = try toStateItem(allocator, field_types[i], name, @field(value, name), 0);
        }
        return items;
    }

    pub fn toStateItem(allocator: Allocator, comptime T: type, key: []const u8, value: T, depth: usize) anyerror!StateItem {
        var item: StateItem = .{
            .key = key,
            .value = "",
            .meta = "",
            .children = &[_]StateItem{},
        };

        if (depth > 6) {
            item.value = "...";
            return item;
        }

        if (comptime isSignalType(T)) {
            item.meta = "(Ref)";
            const val = value.get();
            const ValueT = @TypeOf(val);
            const sub = try toStateItem(allocator, ValueT, key, val, depth + 1);
            item.value = sub.value;
            item.children = sub.children;
            return item;
        }

        if (comptime isComputedType(T)) {
            item.meta = "(Computed)";
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
                var children = try allocator.alloc(StateItem, s.field_types.len);
                inline for (s.field_types, 0..) |field_type, i| {
                    children[i] = try toStateItem(allocator, field_type, s.field_names[i], @field(value, s.field_names[i]), depth + 1);
                }
                item.children = children;
            },
            .pointer => |p| {
                if (p.size == .slice and p.child == u8) {
                    item.value = try std.json.Stringify.valueAlloc(allocator, value, .{});
                } else if (p.size == .slice) {
                    item.value = "Array";
                    var children = try allocator.alloc(StateItem, value.len);
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

    fn serializeProps(allocator: Allocator, comp_fn: zx.Component.ComponentFn) !?[]const StateItem {
        if (comptime builtin.optimize != .debug) return null;
        const json = comp_fn.vtable.dump_props(allocator, comp_fn.data) orelse return null;
        return try stateItemsFromJson(allocator, json);
    }

    fn stateItemsFromJson(allocator: Allocator, json: []const u8) !?[]const StateItem {
        const parsed = std.json.parseFromSlice(std.json.Value, allocator, json, .{}) catch return null;
        // Arena-owned parse tree; caller arena frees it with the rest.
        switch (parsed.value) {
            .object => |obj| {
                var items = try allocator.alloc(StateItem, obj.count());
                var i: usize = 0;
                var it = obj.iterator();
                while (it.next()) |entry| {
                    items[i] = try stateItemFromJsonValue(allocator, entry.key_ptr.*, entry.value_ptr.*);
                    i += 1;
                }
                return items;
            },
            else => return null,
        }
    }

    fn stateItemFromJsonValue(allocator: Allocator, key: []const u8, value: std.json.Value) !StateItem {
        return switch (value) {
            .object => |obj| blk: {
                var children = try allocator.alloc(StateItem, obj.count());
                var i: usize = 0;
                var it = obj.iterator();
                while (it.next()) |entry| {
                    children[i] = try stateItemFromJsonValue(allocator, entry.key_ptr.*, entry.value_ptr.*);
                    i += 1;
                }
                break :blk .{
                    .key = key,
                    .value = "Object",
                    .children = children,
                };
            },
            .array => |arr| blk: {
                var children = try allocator.alloc(StateItem, arr.items.len);
                for (arr.items, 0..) |v, i| {
                    var buf: [32]u8 = undefined;
                    const index_key = try std.fmt.bufPrint(&buf, "{d}", .{i});
                    children[i] = try stateItemFromJsonValue(allocator, try allocator.dupe(u8, index_key), v);
                }
                break :blk .{
                    .key = key,
                    .value = "Array",
                    .children = children,
                };
            },
            .null => .{ .key = key, .value = "null" },
            .bool, .integer, .float, .number_string, .string => .{
                .key = key,
                .value = try std.json.Stringify.valueAlloc(allocator, value, .{}),
            },
        };
    }

    pub fn init(allocator: Allocator, component: zx.Component, options: SerializeOptions) anyerror!ComponentSerializable {
        return switch (component) {
            .none => .{},
            .text => |text| .{ .text = text },
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
            .component_fn => |comp_fn| blk: {
                const props_items = if (options.include_props) try serializeProps(allocator, comp_fn) else null;
                if (comp_fn.isIsland()) {
                    const children_slice = try allocator.alloc(ComponentSerializable, 1);
                    children_slice[0] = try ComponentSerializable.init(allocator, comp_fn.island.?.children.*, options);
                    break :blk .{
                        .component = comp_fn.name,
                        .props = props_items,
                        .children = children_slice,
                    };
                }
                // Resolve component_fn by calling it, then serialize the result
                const resolved = try comp_fn.call();

                const resolved_serializable = try ComponentSerializable.init(allocator, resolved, options);
                const children_slice = try allocator.alloc(ComponentSerializable, 1);
                children_slice[0] = resolved_serializable;
                break :blk .{
                    .component = comp_fn.name,
                    .props = props_items,
                    .children = children_slice,
                };
            },
        };
    }

    pub fn initChildren(allocator: Allocator, children: []const zx.Component, options: SerializeOptions) anyerror![]ComponentSerializable {
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
                .component_fn => {
                    try list.append(allocator, try ComponentSerializable.init(allocator, child, options));
                },
                else => {}, // Skip text, none, etc.
            }
        }
        return list.toOwnedSlice(allocator);
    }

    pub fn serialize(self: ComponentSerializable, writer: *std.Io.Writer) !void {
        try zx.util.zxon.serialize(self, writer, .{});
    }
};
