//! Zli - Build modular, ergonomic, and high-performance CLIs with ease.
//! Batteries included.
//!
//! For more info, visit: https://github.com/xcaeser/zli

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;
const ArrayList = std.ArrayList;

const builtin = @import("lib/builtin.zig");
pub const styles = builtin.styles;
pub const Spinner = @import("lib/spinner.zig");
pub const SpinnerStyles = Spinner.SpinnerStyles;

/// FlagType represents the type of a flag, can be a boolean, integer, or string.
pub const FlagType = enum {
    Bool,
    Int,
    String,
};

/// FlagValue represents the value of a flag, can be a boolean, integer, or string.
pub const FlagValue = union(FlagType) {
    Bool: bool,
    Int: i32,
    String: []const u8,
};

/// Flag represents a flag for a command, example: "--verbose".
///
/// Can be used such as `--verbose true` or `--verbose=22`, or just `--verbose`.
pub const Flag = struct {
    name: []const u8,
    shortcut: ?[]const u8 = null,
    description: []const u8,
    type: FlagType,
    default_value: FlagValue,
    hidden: bool = false,

    fn evaluateValueType(self: *const Flag, value: []const u8) !FlagValue {
        return switch (self.type) {
            .Bool => {
                if (std.mem.eql(u8, value, "true")) return FlagValue{ .Bool = true };
                if (std.mem.eql(u8, value, "false")) return FlagValue{ .Bool = false };
                return error.InvalidBooleanValue;
            },
            .Int => FlagValue{ .Int = try std.fmt.parseInt(i32, value, 10) },
            .String => FlagValue{ .String = value },
        };
    }

    fn safeEvaluate(self: *const Flag, value: []const u8) !FlagValue {
        return self.evaluateValueType(value) catch {
            return error.InvalidFlagValue;
        };
    }
};

/// PositionalArg represents a positional argument for a command
///
/// example: `cli open file.txt`.
pub const PositionalArg = struct {
    name: []const u8,
    description: []const u8,
    required: bool,
    variadic: bool = false,
};

/// CommandContext represents the context of a command execution.
pub const CommandContext = struct {
    root: *Command,
    direct_parent: *Command,
    command: *Command,
    allocator: Allocator,
    writer: *Io.Writer,
    reader: *Io.Reader,
    positional_args: []const []const u8,
    spinner: *Spinner,
    data: ?*anyopaque = null,

    // TODO: fix panic: integer cast truncated bits - later im tired
    pub fn flag(self: *const CommandContext, flag_name: []const u8, comptime T: type) T {
        if (self.command.flag_values.get(flag_name)) |val| {
            return switch (val) {
                .Bool => |b| if (T == bool) b else getDefaultValue(T),
                .Int => |i| if (@typeInfo(T) == .int) @as(T, @intCast(i)) else getDefaultValue(T),
                .String => |s| if (T == []const u8) s else getDefaultValue(T),
            };
        }

        if (self.command.findFlag(flag_name)) |found_flag| {
            return switch (found_flag.default_value) {
                .Bool => |b| if (T == bool) b else getDefaultValue(T),
                .Int => |i| if (@typeInfo(T) == .int) @as(T, @intCast(i)) else getDefaultValue(T),
                .String => |s| if (T == []const u8) s else getDefaultValue(T),
            };
        }

        // Should be unreachable if all flags have defaults and validation is correct.
        unreachable;
    }

    fn getDefaultValue(comptime T: type) T {
        return switch (@typeInfo(T)) {
            .bool => false,
            .int => 0,
            .pointer => |ptr_info| if (ptr_info.child == u8) "" else @compileError("Unsupported pointer type"),
            else => @compileError("Unsupported type for flag"),
        };
    }

    pub fn getArg(self: *const CommandContext, name: []const u8) ?[]const u8 {
        const spec = self.command.positional_args.items;
        for (spec, 0..) |arg, i| {
            if (std.mem.eql(u8, arg.name, name)) {
                if (i < self.positional_args.len) return self.positional_args[i];
                return null; // not provided
            }
        }
        return null; // not defined
    }

    pub fn getContextData(self: *const CommandContext, comptime T: type) *T {
        return @ptrCast(@alignCast(self.data.?));
    }
};

/// ExecFn is the type of function that is executed when the command is executed.
const ExecFn = *const fn (ctx: CommandContext) anyerror!void;

/// CommandOptions represents the metadata for a command, such as the name, description, version, and more.
pub const CommandOptions = struct {
    section_title: []const u8 = "General",
    name: []const u8,
    description: []const u8,
    version: ?std.SemanticVersion = null,
    commands_title: []const u8 = "Available commands",
    shortcut: ?[]const u8 = null,
    aliases: ?[]const []const u8 = null,
    short_description: ?[]const u8 = null,
    help: ?[]const u8 = null,
    usage: ?[]const u8 = null,
    deprecated: bool = false,
    replaced_by: ?[]const u8 = null,
};

/// Represents a single command in the Command Line Interface (CLI),
/// such as "run", "version", or any other user-invoked operation.
/// Each command encapsulates specific functionality or behavior
/// that the CLI can execute.
pub const Command = struct {
    options: CommandOptions,

    flags_by_name: StringHashMap(Flag),
    flags_by_shortcut: StringHashMap(Flag),
    flag_values: StringHashMap(FlagValue),

    positional_args: ArrayList(PositionalArg),

    execFn: ExecFn,

    commands_by_name: StringHashMap(*Command),
    commands_by_shortcut: StringHashMap(*Command),
    command_by_aliases: StringHashMap(*Command),

    parent: ?*Command = null,
    allocator: Allocator,
    writer: *Io.Writer,
    reader: *Io.Reader,

    _max_len: usize = 0,
    _general_padding: usize = 5,

    pub fn init(writer: *Io.Writer, reader: *Io.Reader, allocator: Allocator, options: CommandOptions, execFn: ExecFn) !*Command {
        const cmd = try allocator.create(Command);
        errdefer allocator.destroy(cmd);

        cmd.* = Command{
            .writer = writer,
            .reader = reader,
            .allocator = allocator,
            .options = options,
            .positional_args = ArrayList(PositionalArg).empty,
            .execFn = execFn,
            .flags_by_name = StringHashMap(Flag).init(allocator),
            .flags_by_shortcut = StringHashMap(Flag).init(allocator),
            .flag_values = StringHashMap(FlagValue).init(allocator),
            .commands_by_name = StringHashMap(*Command).init(allocator),
            .commands_by_shortcut = StringHashMap(*Command).init(allocator),
            .command_by_aliases = StringHashMap(*Command).init(allocator),
        };

        const helpFlag: Flag = .{
            .name = "help",
            .description = "Shows the help for a command",
            .shortcut = "h",
            .type = .Bool,
            .default_value = .{ .Bool = false },
        };

        try cmd.addFlag(helpFlag);

        return cmd;
    }

    pub fn deinit(self: *Command) void {
        self.positional_args.deinit(self.allocator);

        self.flags_by_name.deinit();
        self.flags_by_shortcut.deinit();
        self.flag_values.deinit();

        var it = self.commands_by_name.valueIterator();
        while (it.next()) |cmd| {
            cmd.*.deinit();
        }
        self.commands_by_name.deinit();
        self.commands_by_shortcut.deinit();
        self.command_by_aliases.deinit();
        self.allocator.destroy(self);
    }

    pub fn printCommands(self: *const Command) !void {
        if (self.commands_by_name.count() == 0) {
            return;
        }

        try self.writer.print("{s}:\n", .{self.options.commands_title});

        var commands = ArrayList(*Command).empty;
        defer commands.deinit(self.allocator);

        var it = self.commands_by_name.iterator();
        while (it.next()) |entry| {
            try commands.append(self.allocator, entry.value_ptr.*);
        }

        std.sort.insertion(*Command, commands.items, {}, struct {
            pub fn lessThan(_: void, a: *Command, b: *Command) bool {
                return std.mem.order(u8, a.options.name, b.options.name) == .lt;
            }
        }.lessThan);

        try printAlignedCommands(commands.items, self._general_padding, self._max_len);
    }

    pub fn printCommandsBySection(self: *const Command) !void {
        if (self.commands_by_name.count() == 0) {
            return;
        }

        // Map to group commands by their section title.
        var section_map = StringHashMap(ArrayList(*Command)).init(self.allocator);
        defer {
            var it = section_map.valueIterator();
            while (it.next()) |list| {
                list.deinit(self.allocator);
            }
            section_map.deinit();
        }

        var it = self.commands_by_name.valueIterator();
        while (it.next()) |cmd| {
            const section = cmd.*.options.section_title;

            const list = try section_map.getOrPut(section);
            if (!list.found_existing) {
                list.value_ptr.* = ArrayList(*Command).empty;
            }
            try list.value_ptr.*.append(self.allocator, cmd.*);
        }

        var section_keys = ArrayList([]const u8).empty;
        defer section_keys.deinit(self.allocator);

        var key_it = section_map.keyIterator();
        while (key_it.next()) |key| {
            try section_keys.append(self.allocator, key.*);
        }

        std.sort.insertion([]const u8, section_keys.items, {}, struct {
            pub fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                // Sort by command name, not section title
                return std.mem.order(u8, a, b) == .lt;
            }
        }.lessThan);

        for (section_keys.items) |section_name| {
            // We know the key exists, so we can use .?
            const cmds_list = section_map.get(section_name).?;

            try self.writer.print("{s}{s}{s}:\n", .{ styles.BOLD, section_name, styles.RESET });

            std.sort.insertion(*Command, cmds_list.items, {}, struct {
                pub fn lessThan(_: void, a: *Command, b: *Command) bool {
                    return std.mem.order(u8, a.options.name, b.options.name) == .lt;
                }
            }.lessThan);

            try printAlignedCommands(cmds_list.items, self._general_padding, self._max_len);
            try self.writer.print("\n", .{});
        }
    }

    pub fn printFlags(self: *const Command) !void {
        if (self.flags_by_name.count() == 0) {
            return;
        }

        try self.writer.print("Flags:\n", .{});

        var it = self.flags_by_name.valueIterator();

        while (it.next()) |flag| {
            if (flag.shortcut) |shortcut| {
                try self.writer.print("   -{s}, ", .{shortcut});
            } else {
                try self.writer.print("   ", .{});
            }

            try self.writer.print("--{s}", .{flag.name});

            const flag_name_len = flag.name.len + 2; // "--" + name
            const flag_shortcut_len = if (flag.shortcut) |s| s.len + 3 else 0; // account for 3 "-" + shortcut + ", "
            const flag_total_len = flag_name_len + flag_shortcut_len;

            try self.writer.splatByteAll(' ', self._general_padding + self._max_len - flag_total_len);

            try self.writer.print("{s} [{s}]", .{
                flag.description,
                @tagName(flag.type),
            });

            switch (flag.type) {
                .Bool => try self.writer.print(" (default: {s})", .{if (flag.default_value.Bool) "true" else "false"}),
                .Int => try self.writer.print(" (default: {})", .{flag.default_value.Int}),
                .String => if (flag.default_value.String.len > 0) {
                    try self.writer.print(" (default: \"{s}\")", .{flag.default_value.String});
                },
            }
            try self.writer.print("\n", .{});
        }
    }

    pub fn printPositionalArgs(self: *const Command) !void {
        if (self.positional_args.items.len == 0) return;

        try self.writer.print("Arguments:\n", .{});

        for (self.positional_args.items) |arg| {
            try self.writer.print("   {s}", .{arg.name});

            const width = self._general_padding + self._max_len - arg.name.len;
            try self.writer.splatByteAll(' ', width);
            try self.writer.print("{s}", .{arg.description});
            if (arg.required) {
                try self.writer.print(" (required)", .{});
            }
            if (arg.variadic) {
                try self.writer.print(" (variadic)", .{});
            }
            try self.writer.print("\n", .{});
        }

        try self.writer.print("\n", .{});
    }

    pub fn printAliases(self: *Command) !void {
        if (self.options.aliases) |aliases| {
            if (aliases.len == 0) return;
            try self.writer.print("Aliases: ", .{});
            for (aliases, 0..) |alias, i| {
                try self.writer.print("{s}", .{alias});
                if (i < aliases.len - 1) {
                    try self.writer.print(", ", .{});
                }
            }
        }
    }

    pub fn printUsageLine(self: *Command) !void {
        var parents = try self.getParents(self.allocator);
        defer parents.deinit(self.allocator);

        try self.writer.print("Usage: ", .{});

        for (parents.items) |p| {
            try self.writer.print("{s} ", .{p.options.name});
        }

        try self.writer.print("{s} [options]", .{self.options.name});

        for (self.positional_args.items) |arg| {
            if (arg.required) {
                try self.writer.print(" <{s}>", .{arg.name});
            } else {
                try self.writer.print(" [{s}]", .{arg.name});
            }
            if (arg.variadic) {
                try self.writer.print("...", .{});
            }
        }
    }

    pub fn printInfo(self: *const Command) !void {
        try self.writer.print("{s}{s}{s}\n", .{ styles.BOLD, self.options.description, styles.RESET });
        if (self.options.version) |version| try self.writer.print("{s}v{f}{s}\n", .{ styles.DIM, version, styles.RESET });
    }

    pub fn printVersion(self: *const Command) !void {
        if (self.options.version) |version| try self.writer.print("{f}\n", .{version});
    }

    /// Prints traditional help with commands NOT organized by sections
    pub fn printHelp(self: *Command) !void {
        if (!self.options.deprecated) {
            self.calculateMaxLenForWriter();

            try self.printInfo();
            try self.writer.print("\n", .{});

            if (self.options.help) |help| {
                try self.writer.print("{s}\n\n", .{help});
            }

            var parents = try self.getParents(self.allocator);
            defer parents.deinit(self.allocator);

            // Usage
            if (self.options.usage) |usage| {
                try self.writer.print("Usage: {s}\n", .{usage});
            } else {
                try self.printUsageLine();
            }

            if (self.options.aliases) |aliases| {
                if (aliases.len > 0) {
                    try self.writer.print("\n\n", .{});
                }
            }

            // Aliases
            try self.printAliases();

            // Sub commands
            try self.writer.print("\n", .{});

            if (self.commands_by_name.count() > 0) try self.writer.print("\n", .{});
            try self.printCommands();
            try self.writer.print("\n", .{});

            // Flags
            try self.printFlags();
            if (self.flags_by_name.count() > 0) try self.writer.print("\n", .{});

            // Arguments
            try self.printPositionalArgs();

            const has_subcommands = self.commands_by_name.count() > 0;

            try self.writer.print("Use \"", .{});
            for (parents.items) |p| {
                try self.writer.print("{s} ", .{p.options.name});
            }
            try self.writer.print("{s}", .{self.options.name});

            if (has_subcommands) {
                try self.writer.print(" [command]", .{});
            }
            try self.writer.print(" --help\" for more information.\n", .{});
        }
    }

    /// Prints help with commands organized by sections // @TODO: add padding
    pub fn printStructuredHelp(self: *Command) !void {
        if (!self.options.deprecated) {
            self.calculateMaxLenForWriter();

            try self.printInfo();
            try self.writer.print("\n", .{});

            if (self.options.help) |help| {
                try self.writer.print("{s}\n\n", .{help});
            }

            var parents = try self.getParents(self.allocator);
            defer parents.deinit(self.allocator);

            // Usage
            if (self.options.usage) |usage| {
                try self.writer.print("Usage: {s}\n", .{usage});
            } else {
                try self.printUsageLine();
            }

            if (self.options.aliases) |aliases| {
                if (aliases.len > 0) {
                    try self.writer.print("\n\n", .{});
                }
            }

            // Aliases
            try self.printAliases();

            // Sub commands
            try self.writer.print("\n", .{});

            if (self.commands_by_name.count() > 0) try self.writer.print("\n", .{});
            try self.printCommandsBySection();
            try self.writer.print("\n", .{});

            // Flags
            try self.printFlags();
            if (self.flags_by_name.count() > 0) try self.writer.print("\n", .{});

            // Arguments
            try self.printPositionalArgs();

            const has_subcommands = self.commands_by_name.count() > 0;

            try self.writer.print("Use \"", .{});
            for (parents.items) |p| {
                try self.writer.print("{s} ", .{p.options.name});
            }
            try self.writer.print("{s}", .{self.options.name});

            if (has_subcommands) {
                try self.writer.print(" [command]", .{});
            }
            try self.writer.print(" --help\" for more information.\n", .{});
        }
    }

    pub fn getParents(self: *Command, allocator: Allocator) !ArrayList(*Command) {
        var list = ArrayList(*Command).empty;

        var cmd = self;
        while (cmd.parent) |p| {
            try list.append(allocator, p);
            cmd = p;
        }

        std.mem.reverse(*Command, list.items);
        return list;
    }

    pub fn addCommand(self: *Command, command: *Command) !void {
        command.parent = self;
        try self.commands_by_name.put(command.options.name, command);
        if (command.options.aliases) |aliases| {
            for (aliases) |alias| {
                try self.command_by_aliases.put(alias, command);
            }
        }
        if (command.options.shortcut) |shortcut| try self.commands_by_shortcut.put(shortcut, command);
    }

    pub fn addCommands(self: *Command, commands: []const *Command) !void {
        for (commands) |cmd| try self.addCommand(cmd);
    }

    pub fn addPositionalArg(self: *Command, pos_arg: PositionalArg) !void {
        if (self.positional_args.items.len > 0) {
            const last_arg = self.positional_args.items[self.positional_args.items.len - 1];
            if (last_arg.variadic) {
                try self.writer.print("Variadic args should only appear at the end.\n", .{});
                try self.writer.flush();
                std.process.exit(1);
            }
        }
        try self.positional_args.append(self.allocator, pos_arg);
    }

    pub fn addFlag(self: *Command, flag: Flag) !void {
        try self.flags_by_name.put(flag.name, flag);
        if (flag.shortcut) |shortcut| try self.flags_by_shortcut.put(shortcut, flag);

        try self.flag_values.put(flag.name, flag.default_value);
    }

    pub fn addFlags(self: *Command, flags: []const Flag) !void {
        for (flags) |flag| {
            try self.addFlag(flag);
        }
    }

    // cli run --faas pp --me --op=77 -p -abc xxxx yyyy zzzz
    fn parseArgsAndFlags(self: *Command, args: *ArrayList([]const u8), out_positionals: *ArrayList([]const u8)) !void {
        while (args.items.len > 0) {
            const arg = args.items[0];

            if (args.items.len > 0 and
                (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")))
            {
                try self.printHelp();
                std.process.exit(0);
            }

            // Handle flags (all the existing parseFlags logic)
            if (std.mem.startsWith(u8, arg, "--")) {
                // --flag=value
                if (std.mem.indexOf(u8, arg[2..], "=")) |eql_index| {
                    const flag_name = arg[2..][0..eql_index];
                    const value = arg[2 + eql_index + 1 ..];
                    const flag = self.findFlag(flag_name);
                    if (flag == null) {
                        try self.writer.print("Unknown flag: --{s}\n", .{flag_name});
                        try self.displayCommandError();
                        std.process.exit(1);
                    }
                    const flag_value = flag.?.safeEvaluate(value) catch {
                        try self.writer.print("Invalid value for flag --{s}: '{s}'\n", .{ flag_name, value });
                        try self.writer.print("Expected a value of type: {s}\n", .{@tagName(flag.?.type)});
                        try self.displayCommandError();
                        std.process.exit(1);
                    };
                    try self.flag_values.put(flag.?.name, flag_value);
                    _ = args.orderedRemove(0);
                }
                // --flag [value] or boolean
                else {
                    const flag_name = arg[2..];
                    const flag = self.findFlag(flag_name);
                    if (flag == null) {
                        try self.writer.print("Unknown flag: --{s}\n", .{flag_name});
                        try self.displayCommandError();
                        std.process.exit(1);
                    }
                    const has_next = args.items.len > 1;
                    const next_value = if (has_next) args.items[1] else null;

                    if (flag.?.type == .Bool) {
                        if (next_value) |val| {
                            const is_true = std.mem.eql(u8, val, "true");
                            const is_false = std.mem.eql(u8, val, "false");
                            if (is_true or is_false) {
                                try self.flag_values.put(flag.?.name, .{ .Bool = is_true });
                                _ = args.orderedRemove(0); // --flag
                                _ = args.orderedRemove(0); // true/false
                                continue;
                            }
                        }
                        try self.flag_values.put(flag.?.name, .{ .Bool = true });
                        _ = args.orderedRemove(0);
                    } else {
                        if (!has_next) {
                            try self.writer.print("Missing value for flag --{s}\n", .{flag_name});
                            try self.displayCommandError();
                            std.process.exit(1);
                        }
                        const value = args.items[1];
                        const flag_value = flag.?.safeEvaluate(value) catch {
                            try self.writer.print("Invalid value for flag --{s}: '{s}'\n", .{ flag_name, value });
                            try self.writer.print("Expected a value of type: {s}\n", .{@tagName(flag.?.type)});
                            try self.displayCommandError();
                            std.process.exit(1);
                        };
                        try self.flag_values.put(flag.?.name, flag_value);
                        _ = args.orderedRemove(0); // --flag
                        _ = args.orderedRemove(0); // value
                    }
                }
            }
            // -abc short flags
            else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1 and !std.mem.eql(u8, arg, "-")) {
                const shortcuts = arg[1..];
                var j: usize = 0;
                while (j < shortcuts.len) : (j += 1) {
                    const shortcut = shortcuts[j .. j + 1];
                    const flag = self.findFlag(shortcut);
                    if (flag == null) {
                        try self.writer.print("Unknown flag: -{c}\n", .{shortcuts[j]});
                        try self.displayCommandError();
                        std.process.exit(1);
                    }
                    if (flag.?.type == .Bool) {
                        try self.flag_values.put(flag.?.name, .{ .Bool = true });
                    } else {
                        if (j < shortcuts.len - 1) {
                            try self.writer.print("Flag -{c} ({s}) must be last in group since it expects a value\n", .{ shortcuts[j], flag.?.name });
                            try self.writer.flush();
                            std.process.exit(1);
                        }
                        if (args.items.len < 2) {
                            try self.writer.print("Missing value for flag -{c} ({s})\n", .{ shortcuts[j], flag.?.name });
                            try self.writer.flush();
                            std.process.exit(1);
                        }
                        const value = args.items[1];
                        const flag_value = flag.?.safeEvaluate(value) catch {
                            try self.writer.print("Invalid value for flag -{c} ({s}): '{s}'\n", .{ shortcuts[j], flag.?.name, value });
                            try self.writer.print("Expected a value of type: {s}\n", .{@tagName(flag.?.type)});
                            try self.writer.flush();
                            std.process.exit(1);
                        };
                        try self.flag_values.put(flag.?.name, flag_value);
                        _ = args.orderedRemove(0); // value
                    }
                }
                _ = args.orderedRemove(0); // -abc
            }
            // Positional argument
            else {
                const val = args.orderedRemove(0);
                try out_positionals.append(self.allocator, val);
            }
        }
    }

    fn findFlag(self: *Command, name_or_shortcut: []const u8) ?Flag {
        if (self.flags_by_name.get(name_or_shortcut)) |flag| return flag;
        if (self.flags_by_shortcut.get(name_or_shortcut)) |flag| return flag;
        return null;
    }

    fn parsePositionalArgs(self: *Command, args: *ArrayList([]const u8)) !void {
        const expected = self.positional_args.items;

        var required_count: u8 = 0;
        for (expected) |value| {
            if (value.required) required_count += 1;
        }

        if (args.items.len < required_count) {
            try self.writer.print("Missing {d} positional argument(s).\n\nExpected: ", .{required_count});

            var first = true;
            for (expected) |arg| {
                if (arg.required) {
                    if (!first) try self.writer.print(", ", .{});
                    try self.writer.print("{s}", .{arg.name});
                    first = false;
                }
            }

            try self.writer.print("\n", .{});
            try self.displayCommandError();
            return error.MissingArgs;
        }

        if (expected.len > 0) {
            const last_arg = expected[expected.len - 1];
            if (!last_arg.variadic and args.items.len > expected.len) {
                try self.writer.print("Too many positional arguments. Expected at most {}.\n", .{expected.len});
                try self.displayCommandError();
                return error.TooManyArgs;
            }
        }
    }

    pub fn findCommand(self: *const Command, name_or_shortcut: []const u8) ?*Command {
        if (self.commands_by_name.get(name_or_shortcut)) |cmd| return cmd;
        if (self.command_by_aliases.get(name_or_shortcut)) |cmd| return cmd;
        if (self.commands_by_shortcut.get(name_or_shortcut)) |cmd| return cmd;
        return null;
    }

    fn checkDeprecated(self: *const Command) !void {
        if (self.options.deprecated) {
            if (self.options.version) |version| {
                try self.writer.print("'{s}' v{f} is deprecated\n", .{ self.options.name, version });
            } else {
                try self.writer.print("'{s}' is deprecated\n", .{self.options.name});
            }

            if (self.options.replaced_by) |new_cmd_name| {
                try self.writer.print("\nUse '{s}' instead.\n", .{new_cmd_name});
            }

            return error.CommandDeprecated;
        }
    }

    // Traverse the commands to find the last one in the user input
    fn findLeaf(self: *Command, args: *ArrayList([]const u8)) !*Command {
        var current = self;

        while (args.items.len > 0 and !std.mem.startsWith(u8, args.items[0], "-")) {
            const name = args.items[0];
            const maybe_next = current.findCommand(name);

            if (maybe_next == null) {
                // Check if the current command expects positional arguments
                const expects_pos_args = current.positional_args.items.len > 0;
                if (!expects_pos_args) {
                    try current.writer.print("Unknown command: '{s}'\n", .{name});
                    try current.displayCommandError();
                    return error.UnknownCommand;
                }
                break;
            }

            _ = args.orderedRemove(0);
            current = maybe_next.?;
        }

        return current;
    }

    // Need to make find command, parse flags and parse pos_args execution in parallel
    /// Executes the command by handling all positional args, subcommands, flags etc...
    ///
    /// Caller needs to flush the writer after calling this fn.
    /// ```zig
    ///  const root = try cli.build(&writer, allocator);
    ///  defer root.deinit();
    ///  try root.execute(.{});
    ///  try writer.flush();
    /// ```
    pub fn execute(self: *Command, context: struct { data: ?*anyopaque = null, process_args: std.process.Args }) !void {
        errdefer self.writer.flush() catch {};

        var input = try context.process_args.iterateAllocator(self.allocator);
        defer input.deinit();
        _ = input.skip(); // skip program name

        var args = ArrayList([]const u8).empty;
        defer args.deinit(self.allocator);
        while (input.next()) |arg| {
            try args.append(self.allocator, arg);
        }

        var pos_args = ArrayList([]const u8).empty;
        defer pos_args.deinit(self.allocator);

        var cmd = self.findLeaf(&args) catch |err| {
            if (err == error.UnknownCommand) {
                try self.writer.flush();
                std.process.exit(1);
            }
            return err;
        };

        cmd.checkDeprecated() catch {
            try self.writer.flush();
            std.process.exit(1);
        };

        try cmd.parseArgsAndFlags(&args, &pos_args);
        cmd.parsePositionalArgs(&pos_args) catch {
            try self.writer.flush();
            std.process.exit(1);
        };

        var spinner = Spinner.init(cmd.writer, cmd.reader, cmd.allocator, .{});
        defer spinner.deinit();

        const ctx = CommandContext{
            .root = self,
            .direct_parent = cmd.parent orelse self,
            .command = cmd,
            .allocator = cmd.allocator,
            .writer = cmd.writer,
            .reader = cmd.reader,
            .positional_args = pos_args.items,
            .spinner = &spinner,
            .data = context.data,
        };

        try cmd.execFn(ctx);
    }

    fn displayCommandError(self: *Command) !void {
        var parents = try self.getParents(self.allocator);
        defer parents.deinit(self.allocator);

        try self.writer.print("\nRun: '", .{});
        for (parents.items) |p| {
            try self.writer.print("{s} ", .{p.options.name});
        }
        try self.writer.print("{s} --help'\n", .{self.options.name});
        try self.writer.flush();
    }

    fn calculateMaxLenForWriter(self: *Command) void {
        var commands_it = self.commands_by_name.valueIterator();
        var flags_it = self.flags_by_name.valueIterator();
        const args = self.positional_args.items;

        while (commands_it.next()) |cmd| {
            const cmd_name_len = cmd.*.options.name.len;
            const cmd_shortcut_len = if (cmd.*.options.shortcut) |s| s.len + 3 else 0; // account for 3 = " ()"
            const cmd_total_len = cmd_name_len + cmd_shortcut_len;
            self._max_len = @max(self._max_len, cmd_total_len);
        }

        while (flags_it.next()) |flag| {
            const flag_name_len = flag.*.name.len + 2; // "--" + name
            const flag_shortcut_len = if (flag.*.shortcut) |s| s.len + 3 else 0; // account for 3 "-" + shortcut + ", "
            const flag_total_len = flag_name_len + flag_shortcut_len;

            self._max_len = @max(self._max_len, flag_total_len);
        }
        for (args) |arg| {
            const arg_len = arg.name.len;

            self._max_len = @max(self._max_len, arg_len);
        }
    }
};

// HELPER FUNCTIONS

/// Prints a list of commands aligned to the maximum width of the commands.
fn printAlignedCommands(commands: []*Command, padding: usize, max_len: usize) !void {
    for (commands) |cmd| {
        const desc = cmd.options.short_description orelse cmd.options.description;

        try cmd.writer.print("   {s}", .{cmd.options.name});

        if (cmd.options.shortcut) |s| {
            try cmd.writer.print(" ({s})", .{s});
        }

        const cmd_name_len = cmd.options.name.len;
        const cmd_shortcut_len = if (cmd.options.shortcut) |s| s.len + 3 else 0; // account for 3 = " ()"
        const cmd_total_len = cmd_name_len + cmd_shortcut_len;

        const width = padding + max_len - cmd_total_len;
        try cmd.writer.splatByteAll(' ', width);

        try cmd.writer.print("{s}\n", .{desc});
    }
}
