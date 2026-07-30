/// A Key Value store
///
/// Use this to store small pieces of data that need to be shared across requests or persisted across restarts.
///
/// The default zx.kv implementation is a native filesystem based store,
/// stored inside configurable datadir/kv/
///
/// Builtin bindings are provided for WASI for
///
/// - Cloudflare: Workers KV
///
/// and you can implement your own bindings or storage backends if desired.
const Kv = @This();

const std = @import("std");

const zx = @import("../../root.zig");

userdata: ?*anyopaque = null,
vtable: *const VTable,
namespace: []const u8 = "default",

pub const Fs = @import("Kv/Fs.zig");
pub const Wasm = @import("Kv/Wasm.zig");

pub const VTable = struct {
    get: *const fn (userdata: ?*anyopaque, ns: []const u8, allocator: std.mem.Allocator, key: []const u8) anyerror!?[]u8,
    put: *const fn (userdata: ?*anyopaque, ns: []const u8, key: []const u8, value: []const u8, opts: PutOptions) anyerror!void,
    delete: *const fn (userdata: ?*anyopaque, ns: []const u8, key: []const u8) anyerror!void,
    list: *const fn (userdata: ?*anyopaque, ns: []const u8, allocator: std.mem.Allocator, prefix: []const u8) anyerror![][]u8,
};

pub const PutOptions = struct {
    ttl: ?std.Io.Duration = null,
};

pub const KvError = error{
    KvGetFailed,
    KvPutFailed,
    KvDeleteFailed,
    InvalidType,
    KeyTooLong,
};

pub fn get(self: Kv, allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
    return self.vtable.get(self.userdata, self.namespace, allocator, key);
}

pub fn as(self: Kv, allocator: std.mem.Allocator, key: []const u8, comptime T: type) !?T {
    const raw = (try self.vtable.get(self.userdata, self.namespace, allocator, key) orelse return null);
    defer allocator.free(raw);

    const expected_hash = zx.util.zxon.schema(T).hash;
    if (try typeHash(raw) != expected_hash) return error.InvalidType;

    const TypedValue = struct {
        hash: u64,
        value: T,
    };

    const parsed = try zx.util.zxon.parse(TypedValue, allocator, raw, .{});
    return parsed.value;
}

pub fn put(self: Kv, key: []const u8, value: []const u8, opts: PutOptions) !void {
    return self.vtable.put(self.userdata, self.namespace, key, value, opts);
}

pub fn putAs(self: Kv, key: []const u8, value: anytype, opts: PutOptions) !void {
    const ValueType = @TypeOf(value);
    const TypedValue = struct {
        hash: u64,
        value: ValueType,
    };

    var writer = std.Io.Writer.Allocating.init(zx.allocator);
    defer writer.deinit();

    try zx.util.zxon.serialize(TypedValue{
        .hash = zx.util.zxon.schema(ValueType).hash,
        .value = value,
    }, &writer.writer, .{});

    return self.vtable.put(self.userdata, self.namespace, key, writer.written(), opts);
}

pub fn delete(self: Kv, key: []const u8) !void {
    return self.vtable.delete(self.userdata, self.namespace, key);
}

pub fn list(self: Kv, allocator: std.mem.Allocator, prefix: []const u8) ![][]u8 {
    return self.vtable.list(self.userdata, self.namespace, allocator, prefix);
}

pub fn scoped(self: Kv, comptime ns: @EnumLiteral()) Kv {
    return .{ .userdata = self.userdata, .vtable = self.vtable, .namespace = @tagName(ns) };
}

fn typeHash(raw: []const u8) !u64 {
    var i: usize = 0;

    while (i < raw.len and std.ascii.isWhitespace(raw[i])) : (i += 1) {}
    if (i >= raw.len or raw[i] != '[') return error.InvalidType;
    i += 1;

    while (i < raw.len and std.ascii.isWhitespace(raw[i])) : (i += 1) {}
    const start = i;

    while (i < raw.len and std.ascii.isDigit(raw[i])) : (i += 1) {}
    if (start == i) return error.InvalidType;

    return std.fmt.parseUnsigned(u64, raw[start..i], 10);
}

fn failingGet(_: ?*anyopaque, _: []const u8, _: std.mem.Allocator, _: []const u8) anyerror!?[]u8 {
    return error.KvUnavailable;
}
fn failingPut(_: ?*anyopaque, _: []const u8, _: []const u8, _: []const u8, _: PutOptions) anyerror!void {
    return error.KvUnavailable;
}
fn failingDelete(_: ?*anyopaque, _: []const u8, _: []const u8) anyerror!void {
    return error.KvUnavailable;
}
fn failingList(_: ?*anyopaque, _: []const u8, _: std.mem.Allocator, _: []const u8) anyerror![][]u8 {
    return error.KvUnavailable;
}

pub const failing_vtable = VTable{
    .get = &failingGet,
    .put = &failingPut,
    .delete = &failingDelete,
    .list = &failingList,
};

pub const failing = Kv{ .vtable = &failing_vtable };
