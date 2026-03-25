const std = @import("std");

pub fn calcExprSource(allocator: std.mem.Allocator) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    const w = out.writer(allocator);

    try w.writeAll(
        \\pub const CalcExpr = struct {
        \\    const Self = @This();
        \\    pub const Unit = enum { px, em, rem, percent };
        \\    pub const Op = enum { add, sub, mul, div };
        \\    pub const Kind = enum { unit, number, raw, op };
        \\
        \\    pub const Node = struct {
        \\        kind: Kind,
        \\        unit: Unit = .px,
        \\        value: f32 = 0,
        \\        text: []const u8 = "",
        \\        lhs: u8 = 0,
        \\        rhs: u8 = 0,
        \\        op: Op = .add,
        \\    };
        \\
        \\    nodes: [32]Node = undefined,
        \\    len: u8 = 0,
        \\    root: u8 = 0,
        \\
        \\    fn leaf(node: Node) Self {
        \\        var self: Self = undefined;
        \\        self.nodes[0] = node;
        \\        self.len = 1;
        \\        self.root = 0;
        \\        return self;
        \\    }
        \\
        \\    fn unitLeaf(unit: Unit, value: f32) Self {
        \\        return leaf(.{ .kind = .unit, .unit = unit, .value = value });
        \\    }
        \\
        \\    fn numberLeaf(value: f32) Self {
        \\        return leaf(.{ .kind = .number, .value = value });
        \\    }
        \\
        \\    fn rawLeaf(text: []const u8) Self {
        \\        return leaf(.{ .kind = .raw, .text = text });
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
        \\    pub fn raw(text: []const u8) Self {
        \\        return rawLeaf(text);
        \\    }
        \\
        \\    pub fn number(value: f32) Self {
        \\        return numberLeaf(value);
        \\    }
        \\
        \\    fn combine(self: Self, other: Self, op: Op) Self {
        \\        var out = self;
        \\        if (out.len + other.len + 1 > out.nodes.len) @panic("calc expression too complex");
        \\        var i: usize = 0;
        \\        while (i < other.len) : (i += 1) out.nodes[out.len + i] = other.nodes[i];
        \\        const lhs: u8 = out.root;
        \\        const rhs: u8 = @intCast(out.len + other.root);
        \\        out.nodes[out.len + other.len] = .{ .kind = .op, .op = op, .lhs = lhs, .rhs = rhs };
        \\        out.len = @intCast(out.len + other.len + 1);
        \\        out.root = out.len - 1;
        \\        return out;
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
        \\    fn renderNode(self: Self, index: u8, w: *std.io.Writer) !void {
        \\        const node = self.nodes[index];
        \\        switch (node.kind) {
        \\            .unit => switch (node.unit) {
        \\                .percent => try w.print("{d}%", .{node.value}),
        \\                else => try w.print("{d}{s}", .{ node.value, @tagName(node.unit) }),
        \\            },
        \\            .number => try w.print("{d}", .{node.value}),
        \\            .raw => try w.writeAll(node.text),
        \\            .op => {
        \\                try w.writeByte('(');
        \\                try self.renderNode(node.lhs, w);
        \\                try w.print(" {s} ", .{switch (node.op) { .add => "+", .sub => "-", .mul => "*", .div => "/" }});
        \\                try self.renderNode(node.rhs, w);
        \\                try w.writeByte(')');
        \\            },
        \\        }
        \\    }
        \\
        \\    pub fn format(self: Self, w: *std.io.Writer) !void {
        \\        try self.renderNode(self.root, w);
        \\    }
        \\};
    );

    return try out.toOwnedSlice(allocator);
}
