const std = @import("std");

const pltfm = @import("../platform.zig");
const zxon = @import("zxon.zig");

const platform = pltfm.platform;

/// Coerce props to the target struct type, handling defaults
pub fn coerceProps(comptime TargetType: type, props: anytype) TargetType {
    const TargetInfo = @typeInfo(TargetType);
    if (TargetInfo != .@"struct") {
        @compileError("Target type must be a struct");
    }

    const target_struct = TargetInfo.@"struct";
    var result: TargetType = undefined;

    inline for (target_struct.field_names, target_struct.field_types, target_struct.field_attrs) |field_name, field_type, field_attr| {
        if (@hasField(@TypeOf(props), field_name)) {
            @field(result, field_name) = @field(props, field_name);
        } else if (field_attr.defaultValue(field_type)) |default_value| {
            @field(result, field_name) = default_value;
        } else {
            @compileError(std.fmt.comptimePrint("Missing required attribute `{s}` in Component `{s}`", .{ field_name, @typeName(TargetType) }));
        }
    }

    return result;
}

/// Returns props pointer and JSON serializer function for React components
pub fn propsSerializerJson(comptime Props: type, allocator: std.mem.Allocator, props: Props) struct {
    ptr: ?*const anyopaque,
    writeFn: ?*const fn (*std.Io.Writer, *const anyopaque) anyerror!void,
} {
    const type_info = @typeInfo(Props);

    if (type_info != .@"struct") return .{ .ptr = null, .writeFn = null };
    if (type_info.@"struct".field_names.len == 0) return .{ .ptr = null, .writeFn = null };
    if (!comptime isSerializable(Props)) return .{ .ptr = null, .writeFn = null };

    const props_copy = allocator.create(Props) catch return .{ .ptr = null, .writeFn = null };
    props_copy.* = props;

    return .{
        .ptr = props_copy,
        .writeFn = &struct {
            fn write(writer: *std.Io.Writer, ptr: *const anyopaque) anyerror!void {
                const typed_props: *const Props = @ptrCast(@alignCast(ptr));
                try std.json.Stringify.value(typed_props.*, .{}, writer);
            }
        }.write,
    };
}

/// Returns props pointer and serializer function for direct-to-writer serialization at render time.
/// Uses ZXON positional format `[val1, val2, ...]` instead of JSON objects for smaller size.
/// Field names are known at compile time on both server and client, so we only need values.
pub fn propsSerializer(comptime Props: type, allocator: std.mem.Allocator, props: Props) struct {
    ptr: ?*const anyopaque,
    writeFn: ?*const fn (*std.Io.Writer, *const anyopaque) anyerror!void,
} {
    if (platform.role == .client) return .{ .ptr = null, .writeFn = null };
    const type_info = @typeInfo(Props);

    if (type_info != .@"struct") return .{ .ptr = null, .writeFn = null };
    if (type_info.@"struct".field_types.len == 0) return .{ .ptr = null, .writeFn = null };
    if (!comptime isSerializable(Props)) {
        return .{ .ptr = null, .writeFn = null };
    }

    const props_copy = allocator.create(Props) catch return .{ .ptr = null, .writeFn = null };
    props_copy.* = props;

    return .{
        .ptr = props_copy,
        .writeFn = &struct {
            fn write(writer: *std.Io.Writer, ptr: *const anyopaque) anyerror!void {
                const typed_props: *const Props = @ptrCast(@alignCast(ptr));
                try zxon.serialize(typed_props.*, writer, .{});
            }
        }.write,
    };
}

/// Compute the merged type of two structs for props spreading.
/// All fields from both structs are included in the result.
pub fn MergedPropsType(comptime BaseType: type, comptime OverrideType: type) type {
    const base_info = @typeInfo(BaseType);
    const override_info = @typeInfo(OverrideType);

    if (base_info != .@"struct" or override_info != .@"struct") {
        @compileError("MergedPropsType expects struct types");
    }

    const base = base_info.@"struct";
    const override = override_info.@"struct";

    // Count unique fields (override fields replace base fields with same name)
    comptime var field_count = base.field_names.len;
    inline for (override.field_names) |of_name| {
        comptime var found = false;
        inline for (base.field_names) |bf_name| {
            if (std.mem.eql(u8, bf_name, of_name)) {
                found = true;
                break;
            }
        }
        if (!found) field_count += 1;
    }

    comptime var field_names: [field_count][:0]const u8 = undefined;
    comptime var field_types: [field_count]type = undefined;
    comptime var field_attrs: [field_count]std.builtin.Type.Struct.FieldAttributes = undefined;
    comptime var idx: usize = 0;

    // Add base fields (using override's type/attrs when overridden)
    inline for (base.field_names, base.field_types, base.field_attrs) |bf_name, bf_type, bf_attr| {
        comptime var found = false;
        inline for (override.field_names, override.field_types, override.field_attrs) |of_name, of_type, of_attr| {
            if (std.mem.eql(u8, bf_name, of_name)) {
                field_names[idx] = bf_name;
                field_types[idx] = of_type;
                field_attrs[idx] = of_attr;
                found = true;
                break;
            }
        }
        if (!found) {
            field_names[idx] = bf_name;
            field_types[idx] = bf_type;
            field_attrs[idx] = bf_attr;
        }
        idx += 1;
    }

    // Add new fields from override
    inline for (override.field_names, override.field_types, override.field_attrs) |of_name, of_type, of_attr| {
        comptime var found = false;
        inline for (base.field_names) |bf_name| {
            if (std.mem.eql(u8, bf_name, of_name)) {
                found = true;
                break;
            }
        }
        if (!found) {
            field_names[idx] = of_name;
            field_types[idx] = of_type;
            field_attrs[idx] = of_attr;
            idx += 1;
        }
    }

    return @Struct(.auto, null, &field_names, &field_types, &field_attrs);
}

fn isSerializable(comptime T: type) bool {
    return isSerializableImpl(T, &.{});
}

fn isSerializableImpl(comptime T: type, comptime visited: []const type) bool {
    for (visited) |v| {
        if (v == T) return true;
    }

    const new_visited = visited ++ [_]type{T};

    return switch (@typeInfo(T)) {
        .int, .comptime_int, .float, .comptime_float, .bool => true,
        .pointer => |ptr| blk: {
            if (ptr.size == .slice) {
                if (ptr.child == u8) break :blk true;
                if (isSerializableImpl(ptr.child, new_visited)) break :blk true;
            }
            if (ptr.size == .one) {
                const child_info = @typeInfo(ptr.child);
                if (child_info == .array and child_info.array.child == u8) break :blk true;
            }
            break :blk false;
        },
        .array => |arr| isSerializableImpl(arr.child, new_visited),
        .optional => |opt| isSerializableImpl(opt.child, new_visited),
        .@"struct" => |s| blk: {
            for (s.field_types) |field_type| {
                if (!isSerializableImpl(field_type, new_visited)) break :blk false;
            }
            break :blk true;
        },
        .@"enum" => true,
        else => false,
    };
}
