const std = @import("std");

const Io = std.Io;
const Allocator = std.mem.Allocator;

pub fn List(comptime T: type) type {
    return struct {
        head: ?*Node,
        tail: ?*Node,
        mutex: Io.Mutex,

        pub const Node = struct {
            value: T,
            prev: ?*Node = null,
            next: ?*Node = null,
        };

        const Self = @This();

        pub fn init() Self {
            return .{
                .head = null,
                .tail = null,
                .mutex = .init,
            };
        }

        pub fn insert(self: *Self, io: Io, node: *Node) void {
            self.mutex.lockUncancelable(io);
            defer self.mutex.unlock(io);
            self.moveToFrontLocked(node);
        }

        pub fn moveToFront(self: *Self, io: Io, node: *Node) void {
            self.mutex.lockUncancelable(io);
            defer self.mutex.unlock(io);
            self.removeLocked(node);
            self.moveToFrontLocked(node);
        }

        pub fn moveToTail(self: *Self, io: Io, node: *Node) void {
            self.mutex.lockUncancelable(io);
            defer self.mutex.unlock(io);
            self.removeLocked(node);
            self.moveToTailLocked(node);
        }

        pub fn remove(self: *Self, io: Io, node: *Node) void {
            self.mutex.lockUncancelable(io);
            self.removeLocked(node);
            self.mutex.unlock(io);
            node.next = null;
            node.prev = null;
        }

        pub fn removeTail(self: *Self) ?*Node {
            if (self.tail) |node| {
                if (node.prev) |prev| {
                    self.tail = prev;
                    prev.next = null;
                } else {
                    self.tail = null;
                    self.head = null;
                }
                node.next = null;
                node.prev = null;
                return node;
            } else {
                return null;
            }
        }

        fn moveToFrontLocked(self: *Self, node: *Node) void {
            if (self.head) |head| {
                head.prev = node;
                node.next = head;
                self.head = node;
            } else {
                self.head = node;
                self.tail = node;
            }
            node.prev = null;
        }

        fn moveToTailLocked(self: *Self, node: *Node) void {
            if (self.tail) |tail| {
                tail.next = node;
                node.prev = tail;
                self.tail = node;
            } else {
                self.head = node;
                self.tail = node;
            }
            node.next = null;
        }

        fn removeLocked(self: *Self, node: *Node) void {
            if (node.prev) |prev| {
                prev.next = node.next;
            } else {
                self.head = node.next;
            }

            if (node.next) |next| {
                next.prev = node.prev;
            } else {
                self.tail = node.prev;
            }
        }
    };
}

const t = @import("t.zig");

test "list: insert/remove" {
    var list = List(i32).init();
    try testList(list, &.{});

    var e1 = List(i32).Node{ .value = 1 };
    list.insert(t.io, &e1);
    try testList(list, &.{1});
    list.remove(t.io, &e1);
    try testList(list, &.{});
    list.insert(t.io, &e1);

    var e2 = List(i32).Node{ .value = 2 };
    list.insert(t.io, &e2);
    try testList(list, &.{ 2, 1 });
    list.remove(t.io, &e2);
    try testList(list, &.{1});
    list.insert(t.io, &e2);

    var e3 = List(i32).Node{ .value = 3 };
    list.insert(t.io, &e3);
    try testList(list, &.{ 3, 2, 1 });
    list.remove(t.io, &e1);
    try testList(list, &.{ 3, 2 });
    list.remove(t.io, &e2);
    try testList(list, &.{3});
    list.remove(t.io, &e3);
    try testList(list, &.{});
}

test "list: moveToFront" {
    var list = List(i32).init();

    var e1 = List(i32).Node{ .value = 1 };
    list.insert(t.io, &e1);
    list.moveToFront(t.io, &e1);
    try testList(list, &.{1});

    var e2 = List(i32).Node{ .value = 2 };
    list.insert(t.io, &e2);
    list.moveToFront(t.io, &e2);
    try testList(list, &.{ 2, 1 });
    list.moveToFront(t.io, &e1);
    try testList(list, &.{ 1, 2 });
    list.moveToFront(t.io, &e2);
    try testList(list, &.{ 2, 1 });

    var e3 = List(i32).Node{ .value = 3 };
    list.insert(t.io, &e3);
    list.moveToFront(t.io, &e3);
    try testList(list, &.{ 3, 2, 1 });
    list.moveToFront(t.io, &e1);
    try testList(list, &.{ 1, 3, 2 });
    list.moveToFront(t.io, &e2);
    try testList(list, &.{ 2, 1, 3 });
}

test "list: moveToTail" {
    var list = List(i32).init();

    var e1 = List(i32).Node{ .value = 1 };
    list.insert(t.io, &e1);
    list.moveToTail(t.io, &e1);
    try testList(list, &.{1});

    var e2 = List(i32).Node{ .value = 2 };
    list.insert(t.io, &e2);
    list.moveToTail(t.io, &e2);
    try testList(list, &.{ 1, 2 });
    list.moveToTail(t.io, &e1);
    try testList(list, &.{ 2, 1 });
    list.moveToTail(t.io, &e2);
    try testList(list, &.{ 1, 2 });

    var e3 = List(i32).Node{ .value = 3 };
    list.insert(t.io, &e3);
    list.moveToTail(t.io, &e3);
    try testList(list, &.{ 1, 2, 3 });
    list.moveToTail(t.io, &e1);
    try testList(list, &.{ 2, 3, 1 });
    list.moveToTail(t.io, &e2);
    try testList(list, &.{ 3, 1, 2 });
}

test "list: removeTail" {
    var list = List(i32).init();

    var e1 = List(i32).Node{ .value = 1 };
    var e2 = List(i32).Node{ .value = 2 };
    var e3 = List(i32).Node{ .value = 3 };
    list.insert(t.io, &e1);
    try t.expectEqual(@as(i32, 1), list.removeTail().?.value);
    try testList(list, &.{});

    list.insert(t.io, &e1);
    list.insert(t.io, &e2);
    list.insert(t.io, &e3);
    try t.expectEqual(@as(i32, 1), list.removeTail().?.value);
    try testList(list, &.{ 3, 2 });

    try t.expectEqual(@as(i32, 2), list.removeTail().?.value);
    try testList(list, &.{3});

    try t.expectEqual(@as(i32, 3), list.removeTail().?.value);
    try testList(list, &.{});

    try t.expectEqual(true, list.removeTail() == null);
}

fn testList(list: List(i32), expected: []const i32) !void {
    var node = list.head;
    for (expected) |e| {
        try t.expectEqual(e, node.?.value);
        node = node.?.next;
    }
    try t.expectEqual(true, node == null);

    node = list.tail;
    var i: usize = expected.len;
    while (i > 0) : (i -= 1) {
        try t.expectEqual(expected[i - 1], node.?.value);
        node = node.?.prev;
    }
    try t.expectEqual(true, node == null);
}
