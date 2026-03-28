const std = @import("std");

const TypeMap = std.StringArrayHashMap([]const u8);

const UnitSupport = struct {
    length: bool = false,
    angle: bool = false,
    time: bool = false,
    percentage: bool = false,
    color: bool = false,
    shorthand: bool = false,
};

const PropMeta = struct {
    keywords: std.StringArrayHashMap([]const u8),
    units: UnitSupport,
    href: []const u8,
    prose: []const u8 = "",
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const gpa_allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(gpa_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // 1. Load Data
    const main_file = try std.fs.cwd().openFile("vendor/webref/ed/css.json", .{});
    defer main_file.close();
    const main_content = try main_file.readToEndAlloc(allocator, 15 * 1024 * 1024);
    const main_parsed = try std.json.parseFromSlice(std.json.Value, allocator, main_content, .{});

    const root = main_parsed.value.object;
    const properties = root.get("properties").?.array;
    const types_json = root.get("types").?.array;
    const selectors = root.get("selectors").?.array;

    var type_map = TypeMap.init(allocator);
    for (types_json.items) |t| {
        const name = t.object.get("name").?.string;
        const syntax = if (t.object.get("syntax")) |s| s.string else "";
        try type_map.put(name, syntax);
    }

    // 2. Scan Prose
    var prose_map = std.StringHashMap([]const u8).init(allocator);
    var kw_prose_map = std.StringHashMap(std.StringHashMap([]const u8)).init(allocator);
    var dir = try std.fs.cwd().openDir("vendor/webref/ed/css/", .{ .iterate = true });
    defer dir.close();
    var dir_it = dir.iterate();
    while (try dir_it.next()) |entry| {
        if (!std.mem.endsWith(u8, entry.name, ".json")) continue;
        const f = try dir.openFile(entry.name, .{});
        defer f.close();
        const fc = try f.readToEndAlloc(allocator, 5 * 1024 * 1024);
        const p = std.json.parseFromSlice(std.json.Value, allocator, fc, .{}) catch continue;
        if (p.value.object.get("properties")) |props| {
            for (props.array.items) |prop| {
                const name = prop.object.get("name").?.string;
                if (prop.object.get("prose")) |pr| {
                    if (!prose_map.contains(name)) try prose_map.put(name, pr.string);
                }
                if (prop.object.get("values")) |vals| {
                    var kmap = kw_prose_map.get(name) orelse std.StringHashMap([]const u8).init(allocator);
                    for (vals.array.items) |val| {
                        const kname = val.object.get("name").?.string;
                        if (val.object.get("prose")) |pr| {
                            if (!kmap.contains(kname)) try kmap.put(kname, pr.string);
                        }
                    }
                    try kw_prose_map.put(name, kmap);
                }
            }
        }
    }

    var out_file = try std.fs.cwd().createFile("src/style/generated.zig", .{});
    defer out_file.close();
    var buffer: [2 * 1024 * 1024]u8 = undefined;
    var writer = out_file.writer(&buffer);

    try writer.interface.writeAll(
        \\//! Generated from @webref/css (W3C Specifications)
        \\//! Do not edit manually.
        \\
        \\const std = @import("std");
        \\const core = @import("core.zig");
        \\const CssColor = core.Color;
        \\
    );

    var prop_data = std.StringArrayHashMap(PropMeta).init(allocator);
    for (properties.items) |prop| {
        const name = prop.object.get("name").?.string;
        const syntax = if (prop.object.get("syntax")) |s| s.string else "";
        const href = if (prop.object.get("href")) |h| h.string else "";
        var keywords = std.StringArrayHashMap([]const u8).init(allocator);
        try keywords.put("none", "");
        const globals = [_][]const u8{ "inherit", "initial", "revert", "revert-layer", "unset" };
        for (globals) |g| {
            if (!keywords.contains(g)) try keywords.put(g, "");
        }
        var units = UnitSupport{};
        try resolveMetaEnriched(allocator, syntax, &type_map, &keywords, &units, 0, kw_prose_map.get(name));
        try prop_data.put(name, .{ .keywords = keywords, .units = units, .href = href, .prose = prose_map.get(name) orelse "" });
    }

    // Specialized Unions
    var prop_it = prop_data.iterator();
    while (prop_it.next()) |entry| {
        const prop_name = entry.key_ptr.*;
        const data = entry.value_ptr.*;
        const type_name_raw = try cleanName(allocator, prop_name, .pascal);
        const final_type_name = if (std.mem.eql(u8, type_name_raw, "Color")) "CssColor" else type_name_raw;

        if (std.mem.eql(u8, final_type_name, "CssColor")) continue;

        try writer.interface.print("\n/// {s}\n", .{prop_name});
        if (data.prose.len > 0) {
            try writeDoc(&writer.interface, data.prose, "");
            try writer.interface.writeAll("///\n");
        }
        try writer.interface.print("/// - **W3C**: {s}\n", .{data.href});
        try writer.interface.print("pub const {s} = union(enum) {{\n", .{final_type_name});

        var tags = std.StringArrayHashMap(void).init(allocator);

        var k_it = data.keywords.iterator();
        while (k_it.next()) |k_entry| {
            const clean_kw = try cleanName(allocator, k_entry.key_ptr.*, .snake);
            if (clean_kw.len > 0 and !tags.contains(clean_kw)) {
                if (k_entry.value_ptr.*.len > 0) {
                    try writer.interface.writeAll("    /// ");
                    try writeDoc(&writer.interface, k_entry.value_ptr.*, "    ");
                }
                try writer.interface.print("    {s},\n", .{clean_kw});
                try tags.put(clean_kw, {});
            }
        }

        if (data.units.length) try writer.interface.writeAll("    px_: [4]f32, em_: [4]f32, rem_: [4]f32,\n");
        if (data.units.percentage) try writer.interface.writeAll("    percent_: [4]f32,\n");
        if (data.units.color) try writer.interface.writeAll("    hex_: u32,\n");

        // Helper Methods
        if (data.units.length) {
            try writer.interface.print("    pub fn px(v: f32) {s} {{ return .{{ .px_ = .{{ v, v, v, v }} }}; }}\n", .{final_type_name});
            try writer.interface.print("    pub fn px2(v1: f32, v2: f32) {s} {{ return .{{ .px_ = .{{ v1, v2, v1, v2 }} }}; }}\n", .{final_type_name});
            try writer.interface.print("    pub fn px4(v1: f32, v2: f32, v3: f32, v4: f32) {s} {{ return .{{ .px_ = .{{ v1, v2, v3, v4 }} }}; }}\n", .{final_type_name});
            
            try writer.interface.print("    pub fn em(v: f32) {s} {{ return .{{ .em_ = .{{ v, v, v, v }} }}; }}\n", .{final_type_name});
            try writer.interface.print("    pub fn em2(v1: f32, v2: f32) {s} {{ return .{{ .em_ = .{{ v1, v2, v1, v2 }} }}; }}\n", .{final_type_name});
            
            try writer.interface.print("    pub fn rem(v: f32) {s} {{ return .{{ .rem_ = .{{ v, v, v, v }} }}; }}\n", .{final_type_name});
            try writer.interface.print("    pub fn rem2(v1: f32, v2: f32) {s} {{ return .{{ .rem_ = .{{ v1, v2, v1, v2 }} }}; }}\n", .{final_type_name});
        }
        if (data.units.percentage) {
            try writer.interface.print("    pub fn percent(v: f32) {s} {{ return .{{ .percent_ = .{{ v, v, v, v }} }}; }}\n", .{final_type_name});
            try writer.interface.print("    pub fn percent2(v1: f32, v2: f32) {s} {{ return .{{ .percent_ = .{{ v1, v2, v1, v2 }} }}; }}\n", .{final_type_name});
        }
        if (data.units.color) {
            try writer.interface.print("    pub fn hex(v: u32) {s} {{ return .{{ .hex_ = v }}; }}\n", .{final_type_name});
        }

        try writer.interface.print("\n    pub fn format(self: {s}, w: *std.io.Writer) std.io.Writer.Error!void {{ return core.formatValue(self, w); }}\n", .{final_type_name});
        try writer.interface.writeAll("};\n");
    }

    try writer.interface.writeAll("\npub const Style = struct {\n");
    for (properties.items) |prop| {
        const name = prop.object.get("name").?.string;
        const data = prop_data.get(name).?;
        const type_name_raw = try cleanName(allocator, name, .pascal);
        const final_type_name = if (std.mem.eql(u8, type_name_raw, "Color")) "CssColor" else type_name_raw;
        const clean_p = try cleanName(allocator, name, .snake);
        if (clean_p.len == 0) continue;
        try writer.interface.print("\n    /// {s}\n", .{name});
        if (data.prose.len > 0) {
            try writeDoc(&writer.interface, data.prose, "    ");
            try writer.interface.writeAll("    ///\n");
        }
        try writer.interface.print("    /// - **W3C**: {s}\n", .{data.href});
        try writer.interface.print("    {s}: {s} = .none,\n", .{ clean_p, final_type_name });
    }

    try writer.interface.writeAll("\n    // --- Selectors (Pseudo-classes & Elements) --- //\n");
    var selector_tags = std.StringArrayHashMap(void).init(allocator);
    for (selectors.items) |sel| {
        const name = sel.object.get("name").?.string;
        if (std.mem.indexOf(u8, name, "(") != null) continue; // Skip functional selectors for now
        const href = sel.object.get("href").?.string;
        const prose = if (sel.object.get("prose")) |p| p.string else "";
        const clean_s = try cleanName(allocator, name, .snake);
        if (clean_s.len == 0) continue;
        if (selector_tags.contains(clean_s)) continue;
        
        // Skip if it conflicts with a property name
        var is_duplicate = false;
        var p_it = prop_data.iterator();
        while (p_it.next()) |p_entry| {
            const p_clean = try cleanName(allocator, p_entry.key_ptr.*, .snake);
            if (std.mem.eql(u8, p_clean, clean_s)) {
                is_duplicate = true;
                break;
            }
        }
        if (is_duplicate) continue;

        try selector_tags.put(clean_s, {});

        try writer.interface.print("\n    /// {s}\n", .{name});
        if (prose.len > 0) {
            try writeDoc(&writer.interface, prose, "    ");
            try writer.interface.writeAll("    ///\n");
        }
        try writer.interface.print("    /// - **W3C**: {s}\n", .{href});
        try writer.interface.print("    {s}: ?*const Style = null,\n", .{clean_s});
    }

    try writer.interface.writeAll(
        \\
        \\    // Responsive Breakpoints
        \\    sm: ?*const Style = null,
        \\    md: ?*const Style = null,
        \\    lg: ?*const Style = null,
        \\    xl: ?*const Style = null,
        \\
        \\    extra: []const u8 = "",
        \\
        \\    pub fn format(self: Style, w: *std.io.Writer) std.io.Writer.Error!void {
        \\        @setEvalBranchQuota(20000);
        \\        inline for (std.meta.fields(Style)) |f| {
        \\            const T = f.type;
        \\            if (comptime std.mem.eql(u8, f.name, "extra")) continue;
        \\            
        \\            if (comptime @typeInfo(T) == .@"union") {
        \\                const val = @field(self, f.name);
        \\                if (val != .none) {
        \\                    try core.formatKebab(f.name, w);
        \\                    try w.writeAll(": ");
        \\                    try val.format(w);
        \\                    try w.writeAll("; ");
        \\                }
        \\            }
        \\        }
        \\        if (self.extra.len > 0) try w.writeAll(self.extra);
        \\    }
        \\
        \\    pub fn toString(self: Style, allocator: std.mem.Allocator) ![]const u8 {
        \\        var list: std.ArrayList(u8) = .empty;
        \\        defer list.deinit(allocator);
        \\        const w = list.writer(allocator);
        \\        try self.format(w);
        \\        return list.toOwnedSlice(allocator);
        \\    }
        \\};
    );

    try writer.interface.flush();
}

fn writeDoc(writer: anytype, prose: []const u8, indent: []const u8) !void {
    var it = std.mem.tokenizeAny(u8, prose, "\n");
    while (it.next()) |line| {
        try writer.print("{s}/// {s}\n", .{ indent, line });
    }
}

fn cleanName(allocator: std.mem.Allocator, name: []const u8, case: enum { pascal, camel, snake }) ![]const u8 {
    if (name.len == 0) return "";
    var start: usize = 0;
    while (start < name.len and (name[start] == '-' or name[start] == ':')) : (start += 1) {}
    if (start >= name.len) return "";

    // Skip names that are just symbols (e.g. "&", "+", ">", "||")
    if (!std.ascii.isAlphabetic(name[start]) and !std.ascii.isDigit(name[start])) {
        return "";
    }

    var list: std.ArrayList(u8) = .empty;
    var next_upper = (case == .pascal);
    
    for (name[start..]) |c| {
        if (c == '-' or c == ':') {
            if (case == .snake) {
                try list.append(allocator, '_');
            } else {
                next_upper = true;
            }
        } else {
            if (next_upper) {
                try list.append(allocator, std.ascii.toUpper(c));
                next_upper = false;
            } else {
                try list.append(allocator, c);
            }
        }
    }
    const result = try list.toOwnedSlice(allocator);
    if (isZigKeyword(result) or (result.len > 0 and std.ascii.isDigit(result[0]))) {
        const final = try std.fmt.allocPrint(allocator, "@\"{s}\"", .{result});
        return final;
    }
    return result;
}

fn resolveMetaEnriched(allocator: std.mem.Allocator, syntax: []const u8, type_map: *TypeMap, keywords: *std.StringArrayHashMap([]const u8), units: *UnitSupport, depth: usize, kprose: ?std.StringHashMap([]const u8)) !void {
    if (depth > 10) return;
    
    // Check if this syntax allows multiple values (e.g. {1,4} or {1,2})
    const is_shorthand = std.mem.indexOf(u8, syntax, "{1,4}") != null or std.mem.indexOf(u8, syntax, "{1,2}") != null;
    if (is_shorthand) units.shorthand = true;

    var it = std.mem.tokenizeAny(u8, syntax, " |[]\t\r\n&");
    while (it.next()) |token| {
        if (token.len == 0) continue;
        var cleaned = token;
        if (std.mem.indexOfAny(u8, cleaned, "+*?#{")) |idx| cleaned = cleaned[0..idx];
        if (cleaned.len == 0) continue;
        
        // Handle syntax references like <'padding-top'>
        if (std.mem.startsWith(u8, cleaned, "<'")) {
            const ref_name = cleaned[2 .. cleaned.len - 2];
            // We'll just assume length for common box model properties for now 
            // since we can't easily look up property syntax from here without 
            // passing the whole prop_data map.
            if (std.mem.indexOf(u8, ref_name, "padding") != null or 
                std.mem.indexOf(u8, ref_name, "margin") != null or
                std.mem.indexOf(u8, ref_name, "border") != null) {
                units.length = true;
            }
            continue;
        }

        if (std.mem.startsWith(u8, cleaned, "<")) {
            var type_name = cleaned[1..];
            if (std.mem.indexOfAny(u8, type_name, ">[ ")) |idx| type_name = type_name[0..idx];
            if (std.mem.endsWith(u8, type_name, ">")) type_name = type_name[0 .. type_name.len - 1];
            
            const is_length = std.mem.indexOf(u8, type_name, "length") != null;
            const is_percent = std.mem.indexOf(u8, type_name, "percentage") != null;

            if (is_length) {
                units.length = true;
                if (is_shorthand) {
                    // We don't store is_shorthand in UnitSupport yet, but we should probably 
                    // make units.length an enum or bitset to track this if we wanted to be precise.
                    // For now, let's just enable it if length is detected in a shorthand context.
                }
            }
            if (is_percent) units.percentage = true;
            if (std.mem.indexOf(u8, type_name, "angle") != null) units.angle = true;
            if (std.mem.indexOf(u8, type_name, "time") != null) units.time = true;
            if (std.mem.indexOf(u8, type_name, "color") != null) units.color = true;
            
            if (type_map.get(type_name)) |sub_syntax| try resolveMetaEnriched(allocator, sub_syntax, type_map, keywords, units, depth + 1, kprose);
            continue;
        }
        var is_valid = true;
        if (!std.ascii.isAlphabetic(cleaned[0]) and cleaned[0] != '-' and cleaned[0] != '_') {
            if (cleaned.len == 1 and std.ascii.isDigit(cleaned[0])) {} else is_valid = false;
        }
        if (is_valid) {
            for (cleaned) |c| {
                if (!std.ascii.isAlphanumeric(c) and c != '-' and c != '_') {
                    is_valid = false;
                    break;
                }
            }
        }
        if (is_valid and cleaned.len > 0 and !keywords.contains(cleaned)) {
            const pr = blk: {
                if (kprose) |kp| if (kp.get(cleaned)) |p| break :blk p;
                if (std.mem.eql(u8, cleaned, "inherit")) break :blk "The inherit CSS keyword causes the element to take the computed value of the property from its parent element.";
                if (std.mem.eql(u8, cleaned, "initial")) break :blk "The initial CSS keyword applies the initial (or default) value of a property to an element.";
                if (std.mem.eql(u8, cleaned, "unset")) break :blk "The unset CSS keyword resets a property to its inherited value if the property naturally inherits from its parent, and to its initial value otherwise.";
                break :blk "";
            };
            try keywords.put(try allocator.dupe(u8, cleaned), try allocator.dupe(u8, pr));
        }
    }
}

fn isZigKeyword(name: []const u8) bool {
    const keywords = [_][]const u8{
        "addrspace", "align",       "and",   "asm",    "async",       "await",          "break",     "catch",    "comptime",
        "const",     "continue",    "defer", "else",   "enum",        "errdefer",       "error",     "export",   "extern",
        "fn",        "for",         "if",    "inline", "noalias",     "noinline",       "nosuspend", "opaque",   "or",
        "orelse",    "packed",      "pub",   "resume", "return",      "linksection",    "struct",    "suspend",  "switch",
        "test",      "threadlocal", "try",   "union",  "unreachable", "usingnamespace", "var",       "volatile", "while",
    };
    for (keywords) |kw| {
        if (std.mem.eql(u8, name, kw)) return true;
    }
    return false;
}
