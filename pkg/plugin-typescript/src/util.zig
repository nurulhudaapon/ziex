const std = @import("std");
const BuildConfig = @import("TypescriptBuildConfig.zig");

pub const Options = ExcludeFields(BuildConfig, &.{ "project", "inputs" });

pub fn options(config: BuildConfig) Options {
    var result: Options = undefined;
    inline for (@typeInfo(Options).@"struct".field_names) |name| {
        @field(result, name) = @field(config, name);
    }
    return result;
}

fn ExcludeFields(comptime T: type, comptime excluded: []const []const u8) type {
    const info = @typeInfo(T).@"struct";
    comptime var count: usize = 0;
    for (info.field_names) |name| {
        if (!isExcluded(name, excluded)) count += 1;
    }

    var names: [count][:0]const u8 = undefined;
    var types: [count]type = undefined;
    var attrs: [count]std.builtin.Type.Struct.FieldAttributes = undefined;
    var i: usize = 0;
    for (info.field_names, info.field_types, info.field_attrs) |name, ty, attr| {
        if (!isExcluded(name, excluded)) {
            names[i] = name;
            types[i] = ty;
            attrs[i] = attr;
            i += 1;
        }
    }
    return @Struct(.auto, null, &names, &types, &attrs);
}

fn isExcluded(comptime name: []const u8, comptime excluded: []const []const u8) bool {
    for (excluded) |ex| {
        if (std.mem.eql(u8, name, ex)) return true;
    }
    return false;
}
