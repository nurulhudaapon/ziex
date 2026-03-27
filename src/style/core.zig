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

    pub fn format(self: Color, w: *std.io.Writer) std.io.Writer.Error!void {
        switch (self) {
            .none => {},
            .hex_ => |h| try w.print("#{x:0>6}", .{h}),
            .keyword_ => |k| try w.writeAll(k),
            .rgb_ => |c| try w.print("rgb({d},{d},{d})", .{ c.r, c.g, c.b }),
            .rgba_ => |c| try w.print("rgba({d},{d},{d},{d})", .{ c.r, c.g, c.b, c.a }),
        }
    }
};

pub fn formatKebab(name: []const u8, w: *std.io.Writer) std.io.Writer.Error!void {
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

fn formatShorthand(v: [4]f32, unit: []const u8, w: *std.io.Writer) std.io.Writer.Error!void {
    if (v[0] == v[1] and v[1] == v[2] and v[2] == v[3]) {
        try w.print("{d}{s}", .{ v[0], unit });
    } else if (v[0] == v[2] and v[1] == v[3]) {
        try w.print("{d}{s} {d}{s}", .{ v[0], unit, v[1], unit });
    } else {
        try w.print("{d}{s} {d}{s} {d}{s} {d}{s}", .{ v[0], unit, v[1], unit, v[2], unit, v[3], unit });
    }
}

pub fn formatValue(value: anytype, w: *std.io.Writer) std.io.Writer.Error!void {
    @setEvalBranchQuota(10000);
    const T = @TypeOf(value);
    const info = @typeInfo(T).@"union";
    const tag = @as(info.tag_type.?, value);

    if (tag == .none) return;

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

pub const StyleOutput = struct {
    class: []const u8,
    css: []const u8,
};

pub fn formatProperty(prop: anytype, w: *std.io.Writer) std.io.Writer.Error!void {
    const T = @TypeOf(prop);
    const info = @typeInfo(T).@"union";
    const tag = @as(info.tag_type.?, prop);

    inline for (info.fields) |f| {
        if (tag == @field(info.tag_type.?, f.name)) {
            const val = @field(prop, f.name);
            const ValType = @TypeOf(val);

            // Special case for selectors (pseudo-classes, breakpoints, extra)
            if (comptime std.mem.eql(u8, f.name, "extra")) {
                try w.writeAll(val);
                return;
            }

            // Regular property or selector
            if (comptime ValType == ?*const StyleOutput) {
                if (val) |nested| {
                    try formatKebab(f.name, w);
                    try w.print(" {{ {s} }} ", .{nested.css});
                }
                return;
            }

            try formatKebab(f.name, w);
            try w.writeAll(": ");
            if (comptime @hasDecl(ValType, "format")) {
                try val.format(w);
            } else {
                try formatValue(val, w);
            }
            try w.writeAll("; ");
            return;
        }
    }
}

pub fn init(comptime properties: anytype) StyleOutput {
    comptime {
        const PropsType = @TypeOf(properties);
        const props_info = @typeInfo(PropsType);
        if (props_info != .@"struct" or !props_info.@"struct".is_tuple) {
            @compileError("style.init expects a tuple of properties, e.g., .{ .display(.flex) }");
        }

        var css_buf: []const u8 = "";

        var seen_props: []const []const u8 = &.{};

        for (properties) |prop| {
            const tag_name = @tagName(prop);

            for (seen_props) |seen| {
                if (std.mem.eql(u8, seen, tag_name)) {
                    @compileError("Property '" ++ tag_name ++ "' is already defined in this style.");
                }
            }
            seen_props = seen_props ++ [_][]const u8{tag_name};

            var buf: [2048]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&buf);
            var w = fbs.writer();
            formatProperty(prop, &w) catch @panic("OOM in style.init");
            css_buf = css_buf ++ fbs.getWritten();
        }

        const hash = std.hash.Wyhash.hash(0, css_buf);
        const class_name = std.fmt.comptimePrint("zx-{x}", .{hash});

        return .{
            .class = class_name,
            .css = css_buf,
        };
    }
}
