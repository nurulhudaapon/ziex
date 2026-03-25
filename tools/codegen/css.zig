const std = @import("std");
const astgen = @import("astgen.zig");
const helper = @import("helper.zig");

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
    const allocator = gpa.allocator();
    try writeFile(allocator, "src/style/generated.zig");
    std.debug.print("Successfully generated src/style/generated.zig using AST-Driven engine.\n", .{});
}

pub fn writeFile(allocator: std.mem.Allocator, path: []const u8) !void {
    const source = try generate(allocator);
    defer allocator.free(source);

    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(source);
}

pub fn generate(allocator: std.mem.Allocator) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const main_file = try std.fs.cwd().openFile("vendor/webref/ed/css.json", .{});
    defer main_file.close();
    const main_content = try main_file.readToEndAlloc(a, 15 * 1024 * 1024);
    const main_parsed = try std.json.parseFromSlice(std.json.Value, a, main_content, .{});
    defer main_parsed.deinit();

    const root = main_parsed.value.object;
    const properties = root.get("properties").?.array;
    const types_json = root.get("types").?.array;
    const selectors = root.get("selectors").?.array;

    var type_map = TypeMap.init(a);
    defer type_map.deinit();
    for (types_json.items) |t| {
        const name = t.object.get("name").?.string;
        const syntax = if (t.object.get("syntax")) |s| s.string else "";
        try type_map.put(name, syntax);
    }

    var prose_map = std.StringHashMap([]const u8).init(a);
    defer prose_map.deinit();
    var kw_prose_map = std.StringHashMap(std.StringHashMap([]const u8)).init(a);
    defer kw_prose_map.deinit();
    var dir = try std.fs.cwd().openDir("vendor/webref/ed/css/", .{ .iterate = true });
    defer dir.close();
    var dir_it = dir.iterate();
    while (try dir_it.next()) |entry| {
        if (!std.mem.endsWith(u8, entry.name, ".json")) continue;
        const f = try dir.openFile(entry.name, .{});
        defer f.close();
        const fc = try f.readToEndAlloc(a, 5 * 1024 * 1024);
        const p = std.json.parseFromSlice(std.json.Value, a, fc, .{}) catch continue;
        defer p.deinit();
        if (p.value.object.get("properties")) |props| {
            for (props.array.items) |prop| {
                const name = prop.object.get("name").?.string;
                if (prop.object.get("prose")) |pr| {
                    if (!prose_map.contains(name)) try prose_map.put(name, pr.string);
                }
                if (prop.object.get("values")) |vals| {
                    var kmap = kw_prose_map.get(name) orelse std.StringHashMap([]const u8).init(a);
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

    var prop_data = std.StringArrayHashMap(PropMeta).init(a);
    defer prop_data.deinit();
    for (properties.items) |prop| {
        const name = prop.object.get("name").?.string;
        const syntax = if (prop.object.get("syntax")) |s| s.string else "";
        const href = if (prop.object.get("href")) |h| h.string else "";
        var keywords = std.StringArrayHashMap([]const u8).init(a);
        try keywords.put("none", "");
        const globals = [_][]const u8{ "inherit", "initial", "revert", "revert-layer", "unset" };
        for (globals) |g| {
            if (!keywords.contains(g)) try keywords.put(g, "");
        }
        var units = UnitSupport{};
        try resolveMetaEnriched(a, syntax, &type_map, &keywords, &units, 0, kw_prose_map.get(name));
        try prop_data.put(name, .{ .keywords = keywords, .units = units, .href = href, .prose = prose_map.get(name) orelse "" });
    }

    var file = astgen.File.init(allocator);
    defer file.deinit();
    const fa = file.arena.allocator();

    try file.addRaw("//! Generated from @webref/css (W3C Specifications)\n//! Do not edit manually.");
    try file.addImport("std", "std");
    try file.addImport("core", "core.zig");
    try file.addRaw(try helper.calcExprSource(fa));
    _ = try file.addConst("CssColor", "", "core.Color");

    var prop_it = prop_data.iterator();
    while (prop_it.next()) |entry| {
        const prop_name = entry.key_ptr.*;
        const data = entry.value_ptr.*;
        const type_name_raw = try cleanName(a, prop_name, .pascal);
        const final_type_name = if (std.mem.eql(u8, type_name_raw, "Color")) "CssColor" else type_name_raw;

        if (std.mem.eql(u8, final_type_name, "CssColor")) continue;

        const prop_doc = try docText(fa, prop_name, data.prose, data.href);
        const prop_union = try file.addUnion(final_type_name, "enum");
        try prop_union.setDoc(fa, prop_doc);

        var tags = std.StringArrayHashMap(void).init(a);
        var k_it = data.keywords.iterator();
        while (k_it.next()) |k_entry| {
            const clean_kw = try cleanName(a, k_entry.key_ptr.*, .snake);
            if (clean_kw.len > 0 and !tags.contains(clean_kw)) {
                const kw_doc = if (k_entry.value_ptr.*.len > 0) try docText(fa, null, k_entry.value_ptr.*, null) else "";
                try prop_union.addField(fa, kw_doc, clean_kw, "", null);
                try tags.put(clean_kw, {});
            }
        }

        if (data.units.length) {
            try prop_union.addField(fa, "", "px_", "[4]f32", null);
            try prop_union.addField(fa, "", "em_", "[4]f32", null);
            try prop_union.addField(fa, "", "rem_", "[4]f32", null);
        }
        if (data.units.percentage) try prop_union.addField(fa, "", "percent_", "[4]f32", null);
        if (data.units.color) try prop_union.addField(fa, "", "hex_", "u32", null);
        const has_calc = data.units.length or data.units.percentage or data.units.angle or data.units.time;
        if (has_calc) {
            try prop_union.addField(fa, "", "calc_", "CalcExpr", null);
            const calc_sig = try std.fmt.allocPrint(fa, "(expr: CalcExpr) {s}", .{final_type_name});
            _ = try prop_union.addMethod(fa, "", "calc", calc_sig, "return .{ .calc_ = expr };");
        }

        if (data.units.length) {
            const px_sig = try std.fmt.allocPrint(fa, "(v: f32) {s}", .{final_type_name});
            _ = try prop_union.addMethod(fa, "", "px", px_sig, "return .{ .px_ = .{ v, v, v, v } };");

            const px2_sig = try std.fmt.allocPrint(fa, "(v1: f32, v2: f32) {s}", .{final_type_name});
            _ = try prop_union.addMethod(fa, "", "px2", px2_sig, "return .{ .px_ = .{ v1, v2, v1, v2 } };");

            const px4_sig = try std.fmt.allocPrint(fa, "(v1: f32, v2: f32, v3: f32, v4: f32) {s}", .{final_type_name});
            _ = try prop_union.addMethod(fa, "", "px4", px4_sig, "return .{ .px_ = .{ v1, v2, v3, v4 } };");

            const em_sig = try std.fmt.allocPrint(fa, "(v: f32) {s}", .{final_type_name});
            _ = try prop_union.addMethod(fa, "", "em", em_sig, "return .{ .em_ = .{ v, v, v, v } };");

            const em2_sig = try std.fmt.allocPrint(fa, "(v1: f32, v2: f32) {s}", .{final_type_name});
            _ = try prop_union.addMethod(fa, "", "em2", em2_sig, "return .{ .em_ = .{ v1, v2, v1, v2 } };");

            const rem_sig = try std.fmt.allocPrint(fa, "(v: f32) {s}", .{final_type_name});
            _ = try prop_union.addMethod(fa, "", "rem", rem_sig, "return .{ .rem_ = .{ v, v, v, v } };");

            const rem2_sig = try std.fmt.allocPrint(fa, "(v1: f32, v2: f32) {s}", .{final_type_name});
            _ = try prop_union.addMethod(fa, "", "rem2", rem2_sig, "return .{ .rem_ = .{ v1, v2, v1, v2 } };");
        }
        if (data.units.percentage) {
            const pct_sig = try std.fmt.allocPrint(fa, "(v: f32) {s}", .{final_type_name});
            _ = try prop_union.addMethod(fa, "", "percent", pct_sig, "return .{ .percent_ = .{ v, v, v, v } };");

            const pct2_sig = try std.fmt.allocPrint(fa, "(v1: f32, v2: f32) {s}", .{final_type_name});
            _ = try prop_union.addMethod(fa, "", "percent2", pct2_sig, "return .{ .percent_ = .{ v1, v2, v1, v2 } };");
        }
        if (data.units.color) {
            const hex_sig = try std.fmt.allocPrint(fa, "(v: u32) {s}", .{final_type_name});
            _ = try prop_union.addMethod(fa, "", "hex", hex_sig, "return .{ .hex_ = v };");
        }

        const format_sig = try std.fmt.allocPrint(fa, "(self: {s}, w: *std.io.Writer) std.io.Writer.Error!void", .{final_type_name});
        _ = try prop_union.addMethod(fa, "", "format", format_sig, "return core.formatValue(self, w);");
    }

    const style = try file.addStruct("Style");
    for (properties.items) |prop| {
        const name = prop.object.get("name").?.string;
        const data = prop_data.get(name).?;
        const type_name_raw = try cleanName(a, name, .pascal);
        const final_type_name = if (std.mem.eql(u8, type_name_raw, "Color")) "CssColor" else type_name_raw;
        const clean_p = try cleanName(a, name, .snake);
        if (clean_p.len == 0) continue;
        const field_doc = try docText(fa, name, data.prose, data.href);
        try style.addField(fa, field_doc, clean_p, final_type_name, ".none");
    }

    var selector_tags = std.StringArrayHashMap(void).init(a);
    defer selector_tags.deinit();
    for (selectors.items) |sel| {
        const name = sel.object.get("name").?.string;
        if (std.mem.indexOf(u8, name, "(") != null) continue;
        const href = sel.object.get("href").?.string;
        const prose = if (sel.object.get("prose")) |p| p.string else "";
        const clean_s = try cleanName(a, name, .snake);
        if (clean_s.len == 0) continue;
        if (selector_tags.contains(clean_s)) continue;

        var is_duplicate = false;
        var p_it = prop_data.iterator();
        while (p_it.next()) |p_entry| {
            const p_clean = try cleanName(a, p_entry.key_ptr.*, .snake);
            if (std.mem.eql(u8, p_clean, clean_s)) {
                is_duplicate = true;
                break;
            }
        }
        if (is_duplicate) continue;

        try selector_tags.put(clean_s, {});
        const selector_doc = try docText(fa, name, prose, href);
        try style.addField(fa, selector_doc, clean_s, "?*const Style", "null");
    }

    try style.addField(fa, "", "sm", "?*const Style", "null");
    try style.addField(fa, "", "md", "?*const Style", "null");
    try style.addField(fa, "", "lg", "?*const Style", "null");
    try style.addField(fa, "", "xl", "?*const Style", "null");
    try style.addField(fa, "", "extra", "[]const u8", "\"\"");

    _ = try style.addMethod(fa, "", "format", "(self: Style, w: *std.io.Writer) std.io.Writer.Error!void",
        \\@setEvalBranchQuota(20000);
        \\inline for (std.meta.fields(Style)) |f| {
        \\    const T = f.type;
        \\    if (comptime std.mem.eql(u8, f.name, "extra")) continue;
        \\    if (comptime @typeInfo(T) == .@"union") {
        \\        const val = @field(self, f.name);
        \\        if (val != .none) {
        \\            try core.formatKebab(f.name, w);
        \\            try w.writeAll(": ");
        \\            try val.format(w);
        \\            try w.writeAll("; ");
        \\        }
        \\    }
        \\}
        \\if (self.extra.len > 0) try w.writeAll(self.extra);
    );

    _ = try style.addMethod(fa, "", "toString", "(self: Style, allocator: std.mem.Allocator) ![]const u8",
        \\var list: std.ArrayList(u8) = .empty;
        \\defer list.deinit(allocator);
        \\const w = list.writer(allocator);
        \\try self.format(w);
        \\return list.toOwnedSlice(allocator);
    );

    return try file.finish();
}

fn cleanName(allocator: std.mem.Allocator, name: []const u8, case: enum { pascal, camel, snake }) ![]const u8 {
    if (name.len == 0) return "";
    var start: usize = 0;
    while (start < name.len and (name[start] == '-' or name[start] == ':')) : (start += 1) {}
    if (start >= name.len) return "";

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
    // Handle algebraic conflicts by adding a trailing underscore
    if (std.mem.eql(u8, result, "add") or std.mem.eql(u8, result, "sub") or
        std.mem.eql(u8, result, "mul") or std.mem.eql(u8, result, "div"))
    {
        return try std.mem.concat(allocator, u8, &.{ result, "_" });
    }
    return result;
}

fn resolveMetaEnriched(allocator: std.mem.Allocator, syntax: []const u8, type_map: *TypeMap, keywords: *std.StringArrayHashMap([]const u8), units: *UnitSupport, depth: usize, kprose: ?std.StringHashMap([]const u8)) !void {
    if (depth > 10) return;

    const is_shorthand = std.mem.indexOf(u8, syntax, "{1,4}") != null or std.mem.indexOf(u8, syntax, "{1,2}") != null;
    if (is_shorthand) units.shorthand = true;

    var it = std.mem.tokenizeAny(u8, syntax, " |[]\t\r\n&");
    while (it.next()) |token| {
        if (token.len == 0) continue;
        var cleaned = token;
        if (std.mem.indexOfAny(u8, cleaned, "+*?#{")) |idx| cleaned = cleaned[0..idx];
        if (cleaned.len == 0) continue;

        if (std.mem.startsWith(u8, cleaned, "<'")) {
            const ref_name = cleaned[2 .. cleaned.len - 2];
            if (std.mem.indexOf(u8, ref_name, "padding") != null or
                std.mem.indexOf(u8, ref_name, "margin") != null or
                std.mem.indexOf(u8, ref_name, "border") != null)
            {
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

            if (is_length) units.length = true;
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

fn docText(allocator: std.mem.Allocator, title: ?[]const u8, prose: []const u8, href: ?[]const u8) ![]const u8 {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);
    const w = list.writer(allocator);
    var first = true;
    if (title) |t| {
        try w.print("{s}", .{t});
        first = false;
    }
    if (prose.len > 0) {
        if (!first) try w.writeAll("\n\n");
        try w.writeAll(prose);
        first = false;
    }
    if (href) |h| {
        if (!first) try w.writeAll("\n\n");
        try w.print("- **W3C**: {s}", .{h});
    }
    return try list.toOwnedSlice(allocator);
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
