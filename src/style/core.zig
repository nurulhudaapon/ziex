const std = @import("std");

pub const Unit = enum {
    px,
    em,
    rem,
    vh,
    vw,
    vmin,
    vmax,
    @"%",
    pt,
    pc,
    in,
    cm,
    mm,
    deg,
    rad,
    grad,
    turn,
    s,
    ms,
    Hz,
    kHz,
    dpi,
    dpcm,
    dppx,

    pub fn toString(self: Unit) []const u8 {
        return switch (self) {
            .@"%" => "%",
            else => @tagName(self),
        };
    }
};

pub const Dimension = struct {
    value: f32,
    unit: Unit,
};

pub const Color = union(enum) {
    none,
    hex_: u32,
    rgb_: struct { r: u8, g: u8, b: u8 },
    rgba_: struct { r: u8, g: u8, b: u8, a: f32 },
    keyword_: []const u8,

    pub fn hex(val: u32) Color {
        return .{ .hex_ = val };
    }
    pub fn rgb(r: u8, g: u8, b: u8) Color {
        return .{ .rgb_ = .{ .r = r, .g = g, .b = b } };
    }
    pub fn rgba(r: u8, g: u8, b: u8, a: f32) Color {
        return .{ .rgba_ = .{ .r = r, .g = g, .b = b, .a = a } };
    }
    pub fn kw(k: []const u8) Color {
        return .{ .keyword_ = k };
    }

    pub fn format(self: Color, w: anytype) anyerror!void {
        switch (self) {
            .none => {},
            .hex_ => |h| try w.print("#{x:0>6}", .{h}),
            .keyword_ => |k| try w.writeAll(k),
            .rgb_ => |c| try w.print("rgb({d},{d},{d})", .{ c.r, c.g, c.b }),
            .rgba_ => |c| try w.print("rgba({d},{d},{d},{d})", .{ c.r, c.g, c.b, c.a }),
        }
    }
};

pub fn formatKebab(name: []const u8, w: anytype) anyerror!void {
    const prefixes = [_][]const u8{ "webkit", "moz", "ms", "apple", "epub", "hp", "atsc", "rim", "ro", "tc", "xhtml" };
    for (prefixes) |p| {
        if (std.mem.startsWith(u8, name, p) and name.len > p.len and (name[p.len] == '_' or std.ascii.isUpper(name[p.len]))) {
            try w.writeByte('-');
            break;
        }
    }

    for (name, 0..) |c, i| {
        if (c == '_') {
            if (i == name.len - 1) continue; // Skip trailing _ (Zig keyword escape)
            try w.writeByte('-');
        } else if (std.ascii.isUpper(c)) {
            try w.writeByte('-');
            try w.writeByte(std.ascii.toLower(c));
        } else {
            try w.writeByte(c);
        }
    }
}

fn formatShorthand(v: [4]f32, unit: []const u8, w: anytype) anyerror!void {
    if (v[0] == v[1] and v[1] == v[2] and v[2] == v[3]) {
        try w.print("{d}{s}", .{ v[0], unit });
    } else if (v[0] == v[2] and v[1] == v[3]) {
        try w.print("{d}{s} {d}{s}", .{ v[0], unit, v[1], unit });
    } else {
        try w.print("{d}{s} {d}{s} {d}{s} {d}{s}", .{ v[0], unit, v[1], unit, v[2], unit, v[3], unit });
    }
}

pub fn formatValue(value: anytype, w: anytype) anyerror!void {
    @setEvalBranchQuota(100000);
    const T = @TypeOf(value);
    const ti = @typeInfo(T);

    if (ti == .pointer) {
        if (ti.pointer.size == .slice) {
            // Strings/slices
            if (T == []const u8 or T == []u8) {
                try w.writeAll(value);
                return;
            }
        } else {
            return formatValue(value.*, w);
        }
    }

    if (ti == .optional) {
        if (value) |v| return formatValue(v, w);
        return;
    }

    if (ti == .@"union") {
        const info = ti.@"union";
        const tag = @as(info.tag_type.?, value);

        if (comptime @hasField(info.tag_type.?, "none")) {
            if (tag == .none) return;
        }

        inline for (info.fields) |f| {
            if (tag == @field(info.tag_type.?, f.name)) {
                if (comptime std.mem.eql(u8, f.name, "hex_")) {
                    try w.print("#{x:0>6}", .{@field(value, f.name)});
                    return;
                }
                if (comptime f.type == Color) {
                    try @field(value, f.name).format(w);
                    return;
                }
                if (comptime std.mem.eql(u8, f.name, "raw_")) {
                    try w.writeAll(@field(value, f.name));
                    return;
                }

                if (comptime std.mem.eql(u8, f.name, "percent_")) {
                    try formatShorthand(@field(value, f.name), "%", w);
                    return;
                }
                if (comptime std.mem.eql(u8, f.name, "px_")) {
                    try formatShorthand(@field(value, f.name), "px", w);
                    return;
                }
                if (comptime std.mem.eql(u8, f.name, "em_")) {
                    try formatShorthand(@field(value, f.name), "em", w);
                    return;
                }
                if (comptime std.mem.eql(u8, f.name, "rem_")) {
                    try formatShorthand(@field(value, f.name), "rem", w);
                    return;
                }

                if (comptime std.mem.eql(u8, f.name, "calc_")) {
                    try w.writeAll("calc(");
                    try @field(value, f.name).format(w);
                    try w.writeAll(")");
                    return;
                }

                if (comptime std.mem.eql(u8, f.name, "vh_")) {
                    try w.print("{d}vh", .{@field(value, f.name)});
                    return;
                }
                if (comptime std.mem.eql(u8, f.name, "vw_")) {
                    try w.print("{d}vw", .{@field(value, f.name)});
                    return;
                }
                if (comptime std.mem.eql(u8, f.name, "vmin_")) {
                    try w.print("{d}vmin", .{@field(value, f.name)});
                    return;
                }
                if (comptime std.mem.eql(u8, f.name, "vmax_")) {
                    try w.print("{d}vmax", .{@field(value, f.name)});
                    return;
                }

                // Keywords
                try formatKebab(f.name, w);
                return;
            }
        }
    }

    // Default formatting for other types if any
}

pub const StyleOutput = struct {
    class: []const u8,
    css: []const u8,
};

pub fn formatProperty(name: []const u8, val: anytype, w: anytype) anyerror!void {
    @setEvalBranchQuota(100000);
    const T = @TypeOf(val);
    const ti = @typeInfo(T);

    if (ti == .optional) {
        if (val) |v| return formatProperty(name, v, w);
        return;
    }

    if (ti == .pointer) {
        if (ti.pointer.size == .One) {
            return formatProperty(name, val.*, w);
        }
    }

    // Special case for selectors (pseudo-classes, media queries)
    // We check if the value is a struct or a pointer to one that is NOT a Color or other simple type
    const is_style_struct = comptime blk: {
        if (ti == .pointer and ti.pointer.size == .One) {
            const child_ti = @typeInfo(ti.pointer.child);
            break :blk child_ti == .@"struct" and !@hasDecl(ti.pointer.child, "format");
        }
        break :blk ti == .@"struct" and !@hasDecl(T, "format");
    };

    if (is_style_struct) {
        try formatKebab(name, w);
        try w.writeAll(" { ");
        // Recursive call to write nested style
        // Note: This needs access to the init logic or a simplified version
        // For now, let's assume we just want to format its fields
        const info = if (ti == .pointer) @typeInfo(ti.pointer.child).@"struct" else ti.@"struct";
        inline for (info.fields) |f| {
            try formatProperty(f.name, @field(val, f.name), w);
        }
        try w.writeAll("} ");
        return;
    }

    // Check if it's .none
    if (ti == .@"union") {
        const info = ti.@"union";
        if (comptime @hasField(info.tag_type.?, "none")) {
            if (val == .none) return;
        }
    }

    if (std.mem.eql(u8, name, "extra")) {
        if (comptime T == []const u8 or T == ?[]const u8) {
            if (val) |v| try w.writeAll(v);
        }
        return;
    }

    try formatKebab(name, w);
    try w.writeAll(": ");
    if (comptime @hasDecl(T, "format")) {
        try val.format(w);
    } else {
        try formatValue(val, w);
    }
    try w.writeAll("; ");
}

pub fn init(props: anytype) StyleOutput {
    return comptime blk: {
        @setEvalBranchQuota(1000000);
        var css_buf: []const u8 = "";
        const T = @TypeOf(props);
        const ti = @typeInfo(T);

        if (ti == .@"struct") {
            for (ti.@"struct".fields) |f| {
                var buf: [4096]u8 = undefined;
                var fbs = std.io.fixedBufferStream(&buf);
                formatProperty(f.name, @field(props, f.name), fbs.writer()) catch @panic("buffer overflow");
                css_buf = css_buf ++ fbs.getWritten();
            }
        } else if (ti == .pointer or ti == .array) {
            for (props) |p| {
                var buf: [4096]u8 = undefined;
                var fbs = std.io.fixedBufferStream(&buf);
                // For union StyleProperty, we need to extract name and value
                const p_ti = @typeInfo(@TypeOf(p));
                if (p_ti == .@"union") {
                    const tag = @as(p_ti.@"union".tag_type.?, p);
                    for (p_ti.@"union".fields) |uf| {
                        if (tag == @field(p_ti.@"union".tag_type.?, uf.name)) {
                            const val = @field(p, uf.name);
                            // Strip trailing _ from field name if it exists (internal union naming)
                            const clean_name = if (std.mem.endsWith(u8, uf.name, "_")) uf.name[0 .. uf.name.len - 1] else uf.name;
                            formatProperty(clean_name, val, fbs.writer()) catch @panic("buffer overflow");
                        }
                    }
                }
                css_buf = css_buf ++ fbs.getWritten();
            }
        }

        const hash = std.hash.Wyhash.hash(0, css_buf);
        break :blk .{
            .class = std.fmt.comptimePrint("zx-{x}", .{hash}),
            .css = css_buf,
        };
    };
}
