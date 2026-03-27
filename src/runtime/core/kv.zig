const std = @import("std");
const builtin = @import("builtin");
const zx_options = @import("zx_options");

const zx = @import("../../root.zig");

// -- Public types -- //
pub const PutOptions = struct {
    expiration: ?u64 = null,
    expiration_ttl: ?u64 = null,
};

pub const VTable = struct {
    get: *const fn (ctx: *anyopaque, ns: []const u8, allocator: std.mem.Allocator, key: []const u8) anyerror!?[]u8,
    put: *const fn (ctx: *anyopaque, ns: []const u8, key: []const u8, value: []const u8, opts: PutOptions) anyerror!void,
    delete: *const fn (ctx: *anyopaque, ns: []const u8, key: []const u8) anyerror!void,
    list: *const fn (ctx: *anyopaque, ns: []const u8, allocator: std.mem.Allocator, prefix: []const u8) anyerror![][]u8,
};

// -- Global state -- //
var _stateless: u8 = 0;
var _ctx: *anyopaque = @ptrCast(&_stateless);
var _vtable: *const VTable = if (builtin.cpu.arch == .wasm32) &noop_vtable else &filesystem_vtable;

/// Override the active backend. Called once at startup by platform adapters.
pub fn adapter(ctx: *anyopaque, vtable: *const VTable) void {
    _ctx = ctx;
    _vtable = vtable;
}

// -- Default namespace API (uses "default" binding) -- //

pub fn get(allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
    return _vtable.get(_ctx, "default", allocator, key);
}

// Get the value of a key parsed as the given type, returning error if type is not expected,
pub fn as(allocator: std.mem.Allocator, key: []const u8, comptime T: type) !?T {
    return getTyped("default", allocator, key, T);
}

pub fn put(key: []const u8, value: []const u8, opts: PutOptions) !void {
    return _vtable.put(_ctx, "default", key, value, opts);
}

pub fn putAs(key: []const u8, value: anytype, opts: PutOptions) !void {
    return putTyped("default", key, value, opts);
}

pub fn delete(key: []const u8) !void {
    return _vtable.delete(_ctx, "default", key);
}

pub fn list(allocator: std.mem.Allocator, prefix: []const u8) ![][]u8 {
    return _vtable.list(_ctx, "default", allocator, prefix);
}

/// Return a scoped handle that routes all operations to the named KV binding.
///
/// ```zig
/// const users = zx.kv.scope("users");
/// const val = try users.get(ctx.arena, "user-123");
/// ```
pub fn scope(ns: []const u8) KVScope {
    return .{ .ns = ns };
}

pub const KVScope = struct {
    ns: []const u8,

    pub fn get(self: KVScope, allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
        return _vtable.get(_ctx, self.ns, allocator, key);
    }

    pub fn as(self: KVScope, allocator: std.mem.Allocator, key: []const u8, comptime T: type) !?T {
        return getTyped(self.ns, allocator, key, T);
    }

    pub fn put(self: KVScope, key: []const u8, value: []const u8, opts: PutOptions) !void {
        return _vtable.put(_ctx, self.ns, key, value, opts);
    }

    pub fn putAs(self: KVScope, key: []const u8, value: anytype, opts: PutOptions) !void {
        return putTyped(self.ns, key, value, opts);
    }

    pub fn delete(self: KVScope, key: []const u8) !void {
        return _vtable.delete(_ctx, self.ns, key);
    }
    pub fn list(self: KVScope, allocator: std.mem.Allocator, prefix: []const u8) ![][]u8 {
        return _vtable.list(_ctx, self.ns, allocator, prefix);
    }
};

fn getTyped(ns: []const u8, allocator: std.mem.Allocator, key: []const u8, comptime T: type) !?T {
    const raw = (try _vtable.get(_ctx, ns, allocator, key)) orelse return null;
    defer allocator.free(raw);

    const expected_hash = zx.util.zxon.schema(T).hash;
    if (try storedTypeHash(raw) != expected_hash) return error.InvalidType;

    const TypedValue = struct {
        hash: u64,
        value: T,
    };

    const parsed = try zx.util.zxon.parse(TypedValue, allocator, raw, .{});
    return parsed.value;
}

fn putTyped(ns: []const u8, key: []const u8, value: anytype, opts: PutOptions) !void {
    const ValueType = @TypeOf(value);
    const TypedValue = struct {
        hash: u64,
        value: ValueType,
    };

    var writer = std.Io.Writer.Allocating.init(zx.client_allocator);
    defer writer.deinit();

    try zx.util.zxon.serialize(TypedValue{
        .hash = zx.util.zxon.schema(ValueType).hash,
        .value = value,
    }, &writer.writer, .{});

    return _vtable.put(_ctx, ns, key, writer.written(), opts);
}

fn storedTypeHash(raw: []const u8) !u64 {
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

// -- Impl: Noop (WASM default — replaced by edge adapter at startup) -- //

fn noopGet(_: *anyopaque, _: []const u8, _: std.mem.Allocator, _: []const u8) anyerror!?[]u8 {
    return null;
}
fn noopPut(_: *anyopaque, _: []const u8, _: []const u8, _: []const u8, _: PutOptions) anyerror!void {}
fn noopDelete(_: *anyopaque, _: []const u8, _: []const u8) anyerror!void {}
fn noopList(_: *anyopaque, _: []const u8, _: std.mem.Allocator, _: []const u8) anyerror![][]u8 {
    return &[_][]u8{};
}

const noop_vtable = VTable{
    .get = &noopGet,
    .put = &noopPut,
    .delete = &noopDelete,
    .list = &noopList,
};

// -- Impl: Filesystem (native default — persists to datadir/kv/<ns>/) -- //
const kv_store_base = zx_options.datadir ++ std.fs.path.sep_str ++ "kv";

fn keyPath(ns: []const u8, key: []const u8, buf: *[1024]u8) ?[]u8 {
    const encoded_len = std.base64.url_safe_no_pad.Encoder.calcSize(key.len);
    // "<base>/<ns>/<encoded_key>"
    const needed = kv_store_base.len + 1 + ns.len + 1 + encoded_len;
    if (needed > buf.len) return null;
    var pos: usize = 0;
    @memcpy(buf[pos..][0..kv_store_base.len], kv_store_base);
    pos += kv_store_base.len;
    buf[pos] = std.fs.path.sep;
    pos += 1;
    @memcpy(buf[pos..][0..ns.len], ns);
    pos += ns.len;
    buf[pos] = std.fs.path.sep;
    pos += 1;
    const encoded = std.base64.url_safe_no_pad.Encoder.encode(buf[pos..], key);
    return buf[0 .. pos + encoded.len];
}

fn nsDir(ns: []const u8, buf: *[256]u8) ?[]u8 {
    const needed = kv_store_base.len + 1 + ns.len;
    if (needed > buf.len) return null;
    @memcpy(buf[0..kv_store_base.len], kv_store_base);
    buf[kv_store_base.len] = std.fs.path.sep;
    @memcpy(buf[kv_store_base.len + 1 ..][0..ns.len], ns);
    return buf[0..needed];
}

fn fsGet(_: *anyopaque, ns: []const u8, allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
    var buf: [1024]u8 = undefined;
    const path = keyPath(ns, key, &buf) orelse return null;
    const file = std.fs.cwd().openFile(path, .{}) catch return null;
    defer file.close();
    return file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch null;
}

fn fsPut(_: *anyopaque, ns: []const u8, key: []const u8, value: []const u8, _: PutOptions) !void {
    var dir_buf: [256]u8 = undefined;
    const dir_path = nsDir(ns, &dir_buf) orelse return error.KeyTooLong;
    try std.fs.cwd().makePath(dir_path);
    var buf: [1024]u8 = undefined;
    const path = keyPath(ns, key, &buf) orelse return error.KeyTooLong;
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(value);
}

fn fsDelete(_: *anyopaque, ns: []const u8, key: []const u8) !void {
    var buf: [1024]u8 = undefined;
    const path = keyPath(ns, key, &buf) orelse return;
    std.fs.cwd().deleteFile(path) catch {};
}

fn fsList(_: *anyopaque, ns: []const u8, allocator: std.mem.Allocator, prefix: []const u8) ![][]u8 {
    var dir_buf: [256]u8 = undefined;
    const dir_path = nsDir(ns, &dir_buf) orelse return &[_][]u8{};
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return &[_][]u8{};
    defer dir.close();
    var keys = std.ArrayList([]u8).empty;
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        const decoded_len = std.base64.url_safe_no_pad.Decoder.calcSizeForSlice(entry.name) catch continue;
        const key = try allocator.alloc(u8, decoded_len);
        errdefer allocator.free(key);
        std.base64.url_safe_no_pad.Decoder.decode(key, entry.name) catch {
            allocator.free(key);
            continue;
        };
        if (prefix.len == 0 or std.mem.startsWith(u8, key, prefix)) {
            try keys.append(allocator, key);
        } else {
            allocator.free(key);
        }
    }
    return keys.toOwnedSlice(allocator);
}

const filesystem_vtable = VTable{
    .get = &fsGet,
    .put = &fsPut,
    .delete = &fsDelete,
    .list = &fsList,
};
