const Wasm = @This();

const std = @import("std");
const Db = @import("../Db.zig");

binding_name: []u8,
allocator: std.mem.Allocator,

const WireRunResult = struct {
    last_insert_rowid: i64 = 0,
    changes: usize = 0,
};

const WireValueKind = enum {
    null,
    integer,
    float,
    text,
    blob,
    boolean,
};

const WireValue = struct {
    kind: WireValueKind,
    integer: ?i64 = null,
    float: ?f64 = null,
    text: ?[]const u8 = null,
    blob: ?[]const u8 = null,
    boolean: ?bool = null,
};

const WireField = struct {
    name: []const u8,
    value: WireValue,
};

const WireRow = struct {
    fields: []const WireField,
};

const StatementCtx = struct {
    binding_name: []u8,
    sql: []u8,
    allocator: std.mem.Allocator,

    fn deinit(self: *StatementCtx) void {
        self.allocator.free(self.binding_name);
        self.allocator.free(self.sql);
    }
};

// --- Constructors --- //

/// `options` accepts `Db.OpenOptions` (the WASM/D1 backend has no extra knobs).
/// `allocator`/`io` are accepted for signature parity with the other backends;
/// the WASM allocator is always used.
pub fn open(allocator_unused: ?std.mem.Allocator, io: ?std.Io, filename: []const u8, options: Db.OpenOptions) !Db {
    _ = allocator_unused;
    _ = io;
    _ = options;
    const binding_name = filename;
    if (ext.db_open(binding_name.ptr, binding_name.len) < 0) return error.DatabaseOpenFailed;

    const allocator = std.heap.wasm_allocator;
    const self = try allocator.create(Wasm);
    errdefer allocator.destroy(self);

    self.* = .{
        .binding_name = try allocator.dupe(u8, binding_name),
        .allocator = allocator,
    };

    return self.db();
}

pub fn deserialize(_: ?std.mem.Allocator, _: ?std.Io, _: []const u8, _: Db.OpenOptions) !Db {
    return error.Unsupported;
}

pub fn db(self: *Wasm) Db {
    return .{ .userdata = self, .vtable = &database_vtable };
}

fn deinitState(self: *Wasm) void {
    self.allocator.free(self.binding_name);
}

fn prepare(ud: ?*anyopaque, sql: []const u8) !Db.Statement {
    const self: *Wasm = @ptrCast(@alignCast(ud));
    const allocator = self.allocator;

    const statement_ctx = try allocator.create(StatementCtx);
    errdefer allocator.destroy(statement_ctx);

    statement_ctx.* = .{
        .binding_name = try allocator.dupe(u8, self.binding_name),
        .sql = try allocator.dupe(u8, sql),
        .allocator = allocator,
    };

    return .{
        .db = .{ .userdata = ud, .vtable = &database_vtable },
        .handle = @ptrCast(statement_ctx),
    };
}

fn run(ud: ?*anyopaque, sql: []const u8, bindings: Db.Bindings) !Db.RunResult {
    const self: *Wasm = @ptrCast(@alignCast(ud));
    return runQuery(self.binding_name, sql, bindings);
}

fn transaction(_: ?*anyopaque, _: Db.TransactionMode, _: *anyopaque, _: Db.TransactionCallback) !void {
    return error.Unsupported;
}

fn close(ud: ?*anyopaque, _: bool) !void {
    const self: *Wasm = @ptrCast(@alignCast(ud));
    const allocator = self.allocator;
    self.deinitState();
    allocator.destroy(self);
}

fn all(ud: ?*anyopaque, allocator: std.mem.Allocator, bindings: Db.Bindings) ![]const Db.Row {
    const statement_ctx: *StatementCtx = @ptrCast(@alignCast(ud));
    return selectRows(allocator, ext.db_all, statement_ctx.binding_name, statement_ctx.sql, bindings);
}

fn get(ud: ?*anyopaque, allocator: std.mem.Allocator, bindings: Db.Bindings) !?Db.Row {
    const statement_ctx: *StatementCtx = @ptrCast(@alignCast(ud));
    const rows = try selectRows(allocator, ext.db_get, statement_ctx.binding_name, statement_ctx.sql, bindings);
    if (rows.len == 0) {
        allocator.free(rows);
        return null;
    }
    const row = rows[0];
    allocator.free(rows);
    return row;
}

fn runStatement(ud: ?*anyopaque, bindings: Db.Bindings) !Db.RunResult {
    const statement_ctx: *StatementCtx = @ptrCast(@alignCast(ud));
    return runQuery(statement_ctx.binding_name, statement_ctx.sql, bindings);
}

fn values(ud: ?*anyopaque, allocator: std.mem.Allocator, bindings: Db.Bindings) ![]const []const Db.Value {
    const statement_ctx: *StatementCtx = @ptrCast(@alignCast(ud));
    return selectValues(allocator, statement_ctx.binding_name, statement_ctx.sql, bindings);
}

fn iterate(_: ?*anyopaque, _: Db.Bindings) !Db.Statement.Iterator {
    return error.Unsupported;
}

fn finalize(ud: ?*anyopaque) void {
    const statement_ctx: *StatementCtx = @ptrCast(@alignCast(ud));
    const allocator = statement_ctx.allocator;
    statement_ctx.deinit();
    allocator.destroy(statement_ctx);
}

fn toString(ud: ?*anyopaque, allocator: std.mem.Allocator) ![]u8 {
    const statement_ctx: *StatementCtx = @ptrCast(@alignCast(ud));
    return allocator.dupe(u8, statement_ctx.sql);
}

fn columnNames(_: ?*anyopaque) []const []const u8 {
    return &.{};
}

fn columnTypes(_: ?*anyopaque) []const Db.ColumnType {
    return &.{};
}

fn paramsCount(_: ?*anyopaque) usize {
    return 0;
}

fn runQuery(binding_name: []const u8, sql: []const u8, bindings: Db.Bindings) !Db.RunResult {
    var bindings_writer = std.Io.Writer.Allocating.init(std.heap.wasm_allocator);
    defer bindings_writer.deinit();
    try writeBindingsJson(&bindings_writer.writer, bindings);

    var ptr: [*]u8 = undefined;
    const n = ext.db_run(
        binding_name.ptr,
        binding_name.len,
        sql.ptr,
        sql.len,
        bindings_writer.written().ptr,
        bindings_writer.written().len,
        &ptr,
    );
    if (n < 0) return error.DatabaseRunFailed;
    if (n == 0) return error.DatabaseRunFailed;
    defer std.heap.wasm_allocator.free(ptr[0..@intCast(n)]);

    const parsed = try std.json.parseFromSlice(WireRunResult, std.heap.wasm_allocator, ptr[0..@intCast(n)], .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    return .{
        .last_insert_id = parsed.value.last_insert_rowid,
        .changes = parsed.value.changes,
    };
}

fn selectRows(
    allocator: std.mem.Allocator,
    comptime op: anytype,
    binding_name: []const u8,
    sql: []const u8,
    bindings: Db.Bindings,
) ![]const Db.Row {
    var bindings_writer = std.Io.Writer.Allocating.init(std.heap.wasm_allocator);
    defer bindings_writer.deinit();
    try writeBindingsJson(&bindings_writer.writer, bindings);

    var ptr: [*]u8 = undefined;
    const n = op(
        binding_name.ptr,
        binding_name.len,
        sql.ptr,
        sql.len,
        bindings_writer.written().ptr,
        bindings_writer.written().len,
        &ptr,
    );
    if (n < 0) return error.DatabaseQueryFailed;
    if (n == 0) return &[_]Db.Row{};
    defer std.heap.wasm_allocator.free(ptr[0..@intCast(n)]);

    const parsed = try std.json.parseFromSlice([]WireRow, allocator, ptr[0..@intCast(n)], .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    return cloneRows(allocator, parsed.value);
}

fn selectValues(allocator: std.mem.Allocator, binding_name: []const u8, sql: []const u8, bindings: Db.Bindings) ![]const []const Db.Value {
    var bindings_writer = std.Io.Writer.Allocating.init(std.heap.wasm_allocator);
    defer bindings_writer.deinit();
    try writeBindingsJson(&bindings_writer.writer, bindings);

    var ptr: [*]u8 = undefined;
    const n = ext.db_values(
        binding_name.ptr,
        binding_name.len,
        sql.ptr,
        sql.len,
        bindings_writer.written().ptr,
        bindings_writer.written().len,
        &ptr,
    );
    if (n < 0) return error.DatabaseQueryFailed;
    if (n == 0) return &[_][]const Db.Value{};
    defer std.heap.wasm_allocator.free(ptr[0..@intCast(n)]);

    const parsed = try std.json.parseFromSlice([][]WireValue, allocator, ptr[0..@intCast(n)], .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    const rows = try allocator.alloc([]const Db.Value, parsed.value.len);
    for (parsed.value, 0..) |wire_row, row_index| {
        const values_row = try allocator.alloc(Db.Value, wire_row.len);
        for (wire_row, 0..) |wire_value, value_index| {
            values_row[value_index] = try cloneValue(allocator, wire_value);
        }
        rows[row_index] = values_row;
    }
    return rows;
}

fn cloneRows(allocator: std.mem.Allocator, wire_rows: []const WireRow) ![]const Db.Row {
    const rows = try allocator.alloc(Db.Row, wire_rows.len);
    for (wire_rows, 0..) |wire_row, row_index| {
        const fields = try allocator.alloc(Db.Field, wire_row.fields.len);
        for (wire_row.fields, 0..) |wire_field, field_index| {
            fields[field_index] = .{
                .name = try allocator.dupe(u8, wire_field.name),
                .value = try cloneValue(allocator, wire_field.value),
            };
        }
        rows[row_index] = .{ .fields = fields };
    }
    return rows;
}

fn cloneValue(allocator: std.mem.Allocator, wire_value: WireValue) !Db.Value {
    return switch (wire_value.kind) {
        .null => .null,
        .integer => .{ .integer = wire_value.integer orelse 0 },
        .float => .{ .float = wire_value.float orelse 0 },
        .text => .{ .text = try allocator.dupe(u8, wire_value.text orelse "") },
        .blob => .{ .blob = try decodeBlob(allocator, wire_value.blob orelse "") },
        .boolean => .{ .boolean = wire_value.boolean orelse false },
    };
}

fn decodeBlob(allocator: std.mem.Allocator, encoded: []const u8) ![]const u8 {
    const size = try std.base64.standard.Decoder.calcSizeForSlice(encoded);
    const bytes = try allocator.alloc(u8, size);
    _ = try std.base64.standard.Decoder.decode(bytes, encoded);
    return bytes;
}

fn writeBindingsJson(writer: *std.Io.Writer, bindings: Db.Bindings) !void {
    try writer.writeByte('{');
    switch (bindings) {
        .none => try writer.writeAll("\"kind\":\"none\""),
        .positional => |positional_values| {
            try writer.writeAll("\"kind\":\"positional\",\"values\":[");
            for (positional_values, 0..) |value, i| {
                if (i > 0) try writer.writeByte(',');
                try writeValueJson(writer, value);
            }
            try writer.writeByte(']');
        },
        .named => |named_values| {
            try writer.writeAll("\"kind\":\"named\",\"values\":[");
            for (named_values, 0..) |entry, i| {
                if (i > 0) try writer.writeByte(',');
                try writer.writeAll("{\"name\":");
                try std.json.Stringify.value(entry.name, .{}, writer);
                try writer.writeAll(",\"value\":");
                try writeValueJson(writer, entry.value);
                try writer.writeByte('}');
            }
            try writer.writeByte(']');
        },
    }
    try writer.writeByte('}');
}

fn writeValueJson(writer: *std.Io.Writer, value: Db.Value) !void {
    try writer.writeByte('{');
    switch (value) {
        .null => try writer.writeAll("\"kind\":\"null\""),
        .integer => |v| try writer.print("\"kind\":\"integer\",\"integer\":{d}", .{v}),
        .float => |v| try writer.print("\"kind\":\"float\",\"float\":{d}", .{v}),
        .text => |v| {
            try writer.writeAll("\"kind\":\"text\",\"text\":");
            try std.json.Stringify.value(v, .{}, writer);
        },
        .blob => |v| {
            try writer.writeAll("\"kind\":\"blob\",\"blob\":");
            var buf: [4096]u8 = undefined;
            const encoded = std.base64.standard.Encoder.encode(&buf, v);
            try std.json.Stringify.value(encoded, .{}, writer);
        },
        .boolean => |v| try writer.writeAll(if (v) "\"kind\":\"boolean\",\"boolean\":true" else "\"kind\":\"boolean\",\"boolean\":false"),
    }
    try writer.writeByte('}');
}

const ext = struct {
    pub extern "__zx_db" fn db_open(
        ns_ptr: [*]const u8,
        ns_len: usize,
    ) i32;

    pub extern "__zx_db" fn db_run(
        ns_ptr: [*]const u8,
        ns_len: usize,
        sql_ptr: [*]const u8,
        sql_len: usize,
        bindings_ptr: [*]const u8,
        bindings_len: usize,
        out_ptr: *[*]u8,
    ) i32;

    pub extern "__zx_db" fn db_get(
        ns_ptr: [*]const u8,
        ns_len: usize,
        sql_ptr: [*]const u8,
        sql_len: usize,
        bindings_ptr: [*]const u8,
        bindings_len: usize,
        out_ptr: *[*]u8,
    ) i32;

    pub extern "__zx_db" fn db_all(
        ns_ptr: [*]const u8,
        ns_len: usize,
        sql_ptr: [*]const u8,
        sql_len: usize,
        bindings_ptr: [*]const u8,
        bindings_len: usize,
        out_ptr: *[*]u8,
    ) i32;

    pub extern "__zx_db" fn db_values(
        ns_ptr: [*]const u8,
        ns_len: usize,
        sql_ptr: [*]const u8,
        sql_len: usize,
        bindings_ptr: [*]const u8,
        bindings_len: usize,
        out_ptr: *[*]u8,
    ) i32;
};

const database_vtable = Db.VTable{
    .prepare = &prepare,
    .run = &run,
    .transaction = &transaction,
    .close = &close,
    .stmtAll = &all,
    .stmtGet = &get,
    .stmtRun = &runStatement,
    .stmtValues = &values,
    .stmtIterate = &iterate,
    .stmtFinalize = &finalize,
    .stmtToString = &toString,
    .stmtColumnNames = &columnNames,
    .stmtColumnTypes = &columnTypes,
    .stmtParamsCount = &paramsCount,
};
