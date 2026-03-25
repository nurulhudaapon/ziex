const std = @import("std");

pub fn calcExprSource(allocator: std.mem.Allocator) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    const w = out.writer(allocator);

    try w.writeAll(
        \\pub const CalcExpr = struct {
        \\    const Self = @This();
        \\    pub const Unit = enum {
        \\        px,
        \\        em,
        \\        rem,
        \\        percent,
        \\        pub fn toString(self: Unit) []const u8 {
        \\            return switch (self) {
        \\                .percent => "%",
        \\                else => @tagName(self),
        \\            };
        \\        }
        \\    };
        \\
        \\    pub const Op = enum {
        \\        add,
        \\        sub,
        \\        mul,
        \\        div,
        \\        pub fn toString(self: Op) []const u8 {
        \\            return switch (self) {
        \\                .add => "+",
        \\                .sub => "-",
        \\                .mul => "*",
        \\                .div => "/",
        \\            };
        \\        }
        \\    };
        \\
        \\    buf: [64]u8 = undefined,
        \\    len: u8 = 0,
        \\
        \\    fn init(t: []const u8) Self {
        \\        var self: Self = undefined;
        \\        if (t.len > self.buf.len) @panic("calc expression too complex");
        \\        std.mem.copyForwards(u8, self.buf[0..t.len], t);
        \\        self.len = @intCast(t.len);
        \\        return self;
        \\    }
        \\
        \\    fn text(self: Self) []const u8 {
        \\        return self.buf[0..self.len];
        \\    }
        \\
        \\    fn leaf(value: []const u8) Self {
        \\        return init(value);
        \\    }
        \\
        \\    fn unitLeaf(unit: Unit, value: f32) Self {
        \\        var temp: [64]u8 = undefined;
        \\        const written = std.fmt.bufPrint(&temp, "{d}{s}", .{ value, unit.toString() }) catch @panic("calc expression too complex");
        \\        return leaf(written);
        \\    }
        \\
        \\    fn numberLeaf(value: f32) Self {
        \\        var temp: [64]u8 = undefined;
        \\        const written = std.fmt.bufPrint(&temp, "{d}", .{value}) catch @panic("calc expression too complex");
        \\        return leaf(written);
        \\    }
        \\
        \\    fn rawLeaf(value: []const u8) Self {
        \\        return leaf(value);
        \\    }
        \\
        \\    pub fn px(value: f32) Self {
        \\        return unitLeaf(.px, value);
        \\    }
        \\
        \\    pub fn em(value: f32) Self {
        \\        return unitLeaf(.em, value);
        \\    }
        \\
        \\    pub fn rem(value: f32) Self {
        \\        return unitLeaf(.rem, value);
        \\    }
        \\
        \\    pub fn percent(value: f32) Self {
        \\        return unitLeaf(.percent, value);
        \\    }
        \\
        \\    pub fn raw(value: []const u8) Self {
        \\        return rawLeaf(value);
        \\    }
        \\
        \\    pub fn number(value: f32) Self {
        \\        return numberLeaf(value);
        \\    }
        \\
        \\    fn combine(self: Self, other: Self, op: Op) Self {
        \\        var temp: [64]u8 = undefined;
        \\        const lhs = self.text();
        \\        const rhs = other.text();
        \\        const op_text = op.toString();
        \\        const needed = lhs.len + rhs.len + op_text.len + 4;
        \\        if (needed > temp.len) @panic("calc expression too complex");
        \\
        \\        var i: usize = 0;
        \\        temp[i] = '(';
        \\        i += 1;
        \\        std.mem.copyForwards(u8, temp[i..][0..lhs.len], lhs);
        \\        i += lhs.len;
        \\        temp[i] = ' ';
        \\        i += 1;
        \\        std.mem.copyForwards(u8, temp[i..][0..op_text.len], op_text);
        \\        i += op_text.len;
        \\        temp[i] = ' ';
        \\        i += 1;
        \\        std.mem.copyForwards(u8, temp[i..][0..rhs.len], rhs);
        \\        i += rhs.len;
        \\        temp[i] = ')';
        \\        i += 1;
        \\
        \\        return init(temp[0..i]);
        \\    }
        \\
        \\    pub fn add(self: Self, other: Self) Self {
        \\        return self.combine(other, .add);
        \\    }
        \\
        \\    pub fn sub(self: Self, other: Self) Self {
        \\        return self.combine(other, .sub);
        \\    }
        \\
        \\    pub fn mul(self: Self, factor: f32) Self {
        \\        return self.combine(numberLeaf(factor), .mul);
        \\    }
        \\
        \\    pub fn div(self: Self, factor: f32) Self {
        \\        return self.combine(numberLeaf(factor), .div);
        \\    }
        \\
        \\    pub fn format(self: Self, w: *std.io.Writer) !void {
        \\        try w.writeAll(self.text());
        \\    }
        \\};
    );

    return try out.toOwnedSlice(allocator);
}
