const std = @import("std");
const cli_args = @import("cli_args");

pub const DocArg = struct {
    name: []const u8,
    description: []const u8,
};

pub const DocCommand = struct {
    name: []const u8,
    id: []const u8,
    description: []const u8,
    usage: []const u8,
    arguments: []const DocArg,
    flags: []const DocArg,
};

fn usageLine(comptime cmd: cli_args.Command) [:0]const u8 {
    comptime var result: [:0]const u8 = "zx " ++ @tagName(cmd.name);
    inline for (cmd.positional_args) |arg| {
        result = result ++ " " ++ positionalArgLabel(arg);
    }
    if (cmd.named_args.len > 0) result = result ++ " [flags]";
    return result;
}

fn namedArgLabel(comptime arg: cli_args.Argument) [:0]const u8 {
    const long = "--" ++ arg.name;
    if (arg.short) |s| {
        const short = [_]u8{s};
        if (arg.type == bool) return long ++ ", -" ++ short;
        return long ++ ", -" ++ short ++ " <" ++ arg.name ++ ">";
    }
    if (arg.type == bool) return long;
    return long ++ " <" ++ arg.name ++ ">";
}

fn positionalArgLabel(comptime arg: cli_args.Argument) [:0]const u8 {
    return if (arg.isOptional()) "[" ++ arg.name ++ "]" else "<" ++ arg.name ++ ">";
}

fn anchorId(comptime cmd: cli_args.Command) [:0]const u8 {
    return "cli-" ++ @tagName(cmd.name);
}

fn formatOneDefault(comptime T: type, comptime value: T) [:0]const u8 {
    return switch (@typeInfo(T)) {
        .bool => if (value) "true" else "false",
        .int, .float => std.fmt.comptimePrint("{d}", .{value}),
        .pointer => |pointer| switch (pointer.size) {
            .slice, .c, .many => if (pointer.child == u8)
                "\"" ++ value ++ "\""
            else
                comptime unreachable,
            else => comptime unreachable,
        },
        .@"enum" => @tagName(value),
        .optional => "null",
        else => comptime unreachable,
    };
}

fn defaultSuffix(comptime arg: cli_args.Argument) [:0]const u8 {
    const default_value = arg.attrs.defaultValue(arg.type) orelse return "";
    // Optional args always default to null; skip that noise in docs.
    if (@typeInfo(arg.type) == .optional) return "";
    return switch (arg.count) {
        .one => " (default: " ++ formatOneDefault(@TypeOf(default_value), default_value) ++ ")",
        .unlimited => if (default_value.len == 0)
            " (default: <empty>)"
        else blk: {
            comptime var result: [:0]const u8 = " (default:";
            inline for (default_value) |v| {
                result = result ++ " " ++ formatOneDefault(@TypeOf(v), v);
            }
            break :blk result ++ ")";
        },
    };
}

fn argDescription(comptime arg: cli_args.Argument) [:0]const u8 {
    return arg.help ++ defaultSuffix(arg);
}

fn positionalDocs(comptime cmd: cli_args.Command) []const DocArg {
    var list: [cmd.positional_args.len]DocArg = undefined;
    for (cmd.positional_args, 0..) |arg, i| {
        list[i] = .{
            .name = positionalArgLabel(arg),
            .description = argDescription(arg),
        };
    }
    const frozen = list;
    return &frozen;
}

fn namedDocs(comptime cmd: cli_args.Command) []const DocArg {
    var list: [cmd.named_args.len]DocArg = undefined;
    for (cmd.named_args, 0..) |arg, i| {
        list[i] = .{
            .name = namedArgLabel(arg),
            .description = argDescription(arg),
        };
    }
    const frozen = list;
    return &frozen;
}

pub const docs: []const DocCommand = blk: {
    var list: [cli_args.commands.len]DocCommand = undefined;
    for (cli_args.commands, 0..) |cmd, i| {
        list[i] = .{
            .name = @tagName(cmd.name),
            .id = anchorId(cmd),
            .description = cmd.help_short,
            .usage = usageLine(cmd),
            .arguments = positionalDocs(cmd),
            .flags = namedDocs(cmd),
        };
    }
    const frozen = list;
    break :blk &frozen;
};
