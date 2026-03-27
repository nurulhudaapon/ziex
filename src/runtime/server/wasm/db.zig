const std = @import("std");
const db = @import("db");
const ext = @import("extern.zig");

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

const DatabaseCtx = struct {
    binding_name: []u8,
    allocator: std.mem.Allocator,

    fn deinit(self: *DatabaseCtx) void {
        self.allocator.free(self.binding_name);
    }
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

fn open(_: *anyopaque, filename: ?[]const u8, _: db.OpenOptions) !db.Database {
    const binding_name = filename orelse "default";
    if (ext.db_open(binding_name.ptr, binding_name.len) < 0) return error.DatabaseOpenFailed;

    const allocator = std.heap.wasm_allocator;
    const ctx = try allocator.create(DatabaseCtx);
    errdefer allocator.destroy(ctx);

    ctx.* = .{
        .binding_name = try allocator.dupe(u8, binding_name),
        .allocator = allocator,
    };

    return .{
        .backend_ctx = @ptrCast(ctx),
        .vtable = &database_vtable,
    };
}

fn deserialize(_: *anyopaque, _: []const u8, _: db.OpenOptions) !db.Database {
    return error.Unsupported;
}

fn query(ctx: *anyopaque, sql: []const u8) !db.Statement {
    return prepare(ctx, sql);
}

fn prepare(ctx: *anyopaque, sql: []const u8) !db.Statement {
    const database_ctx: *DatabaseCtx = @ptrCast(@alignCast(ctx));
    const allocator = database_ctx.allocator;

    const statement_ctx = try allocator.create(StatementCtx);
    errdefer allocator.destroy(statement_ctx);

    statement_ctx.* = .{
        .binding_name = try allocator.dupe(u8, database_ctx.binding_name),
        .sql = try allocator.dupe(u8, sql),
        .allocator = allocator,
    };

    return .{
        .backend_ctx = @ptrCast(statement_ctx),
        .vtable = &statement_vtable,
    };
}

fn run(ctx: *anyopaque, sql: []const u8, bindings: db.Bindings) !db.RunResult {
    const database_ctx: *DatabaseCtx = @ptrCast(@alignCast(ctx));
    return runQuery(database_ctx.binding_name, sql, bindings);
}

fn transaction(_: *anyopaque, _: db.TransactionMode, _: *anyopaque, _: db.TransactionCallback) !void {
    return error.Unsupported;
}

fn close(ctx: *anyopaque, _: bool) !void {
    const database_ctx: *DatabaseCtx = @ptrCast(@alignCast(ctx));
    const allocator = database_ctx.allocator;
    database_ctx.deinit();
    allocator.destroy(database_ctx);
}

fn serialize(_: *anyopaque, _: std.mem.Allocator) ![]u8 {
    return error.Unsupported;
}

fn loadExtension(_: *anyopaque, _: []const u8, _: ?[]const u8) !void {
    return error.Unsupported;
}

fn fileControl(_: *anyopaque, _: i32, _: db.FileControlValue) !void {
    return error.Unsupported;
}

fn native(_: *anyopaque) ?*anyopaque {
    return null;
}

fn all(ctx: *anyopaque, allocator: std.mem.Allocator, bindings: db.Bindings) ![]const db.Row {
    const statement_ctx: *StatementCtx = @ptrCast(@alignCast(ctx));
    return selectRows(allocator, ext.db_all, statement_ctx.binding_name, statement_ctx.sql, bindings);
}

fn get(ctx: *anyopaque, allocator: std.mem.Allocator, bindings: db.Bindings) !?db.Row {
    const statement_ctx: *StatementCtx = @ptrCast(@alignCast(ctx));
    const rows = try selectRows(allocator, ext.db_get, statement_ctx.binding_name, statement_ctx.sql, bindings);
    if (rows.len == 0) {
        allocator.free(rows);
        return null;
    }
    const row = rows[0];
    allocator.free(rows);
    return row;
}

fn runStatement(ctx: *anyopaque, bindings: db.Bindings) !db.RunResult {
    const statement_ctx: *StatementCtx = @ptrCast(@alignCast(ctx));
    return runQuery(statement_ctx.binding_name, statement_ctx.sql, bindings);
}

fn values(ctx: *anyopaque, allocator: std.mem.Allocator, bindings: db.Bindings) ![]const []const db.Value {
    const statement_ctx: *StatementCtx = @ptrCast(@alignCast(ctx));
    return selectValues(allocator, statement_ctx.binding_name, statement_ctx.sql, bindings);
}

fn iterate(_: *anyopaque, _: db.Bindings) !db.Statement.Iterator {
    return error.Unsupported;
}

fn finalize(ctx: *anyopaque) void {
    const statement_ctx: *StatementCtx = @ptrCast(@alignCast(ctx));
    const allocator = statement_ctx.allocator;
    statement_ctx.deinit();
    allocator.destroy(statement_ctx);
}

fn toString(ctx: *anyopaque, allocator: std.mem.Allocator) ![]u8 {
    const statement_ctx: *StatementCtx = @ptrCast(@alignCast(ctx));
    return allocator.dupe(u8, statement_ctx.sql);
}

fn columnNames(_: *anyopaque) []const []const u8 {
    return &.{};
}

fn columnTypes(_: *anyopaque) []const db.ColumnType {
    return &.{};
}

fn declaredTypes(_: *anyopaque) []const ?[]const u8 {
    return &.{};
}

fn paramsCount(_: *anyopaque) usize {
    return 0;
}

fn runQuery(binding_name: []const u8, sql: []const u8, bindings: db.Bindings) !db.RunResult {
    var bindings_writer = std.Io.Writer.Allocating.init(std.heap.wasm_allocator);
    defer bindings_writer.deinit();
    try writeBindingsJson(&bindings_writer.writer, bindings);

    var buf: [8192]u8 = undefined;
    const n = ext.db_run(
        binding_name.ptr,
        binding_name.len,
        sql.ptr,
        sql.len,
        bindings_writer.written().ptr,
        bindings_writer.written().len,
        &buf,
        buf.len,
    );
    if (n < 0) return error.DatabaseRunFailed;

    const parsed = try std.json.parseFromSlice(WireRunResult, std.heap.wasm_allocator, buf[0..@intCast(n)], .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    return .{
        .last_insert_rowid = parsed.value.last_insert_rowid,
        .changes = parsed.value.changes,
    };
}

fn selectRows(
    allocator: std.mem.Allocator,
    comptime op: anytype,
    binding_name: []const u8,
    sql: []const u8,
    bindings: db.Bindings,
) ![]const db.Row {
    var bindings_writer = std.Io.Writer.Allocating.init(std.heap.wasm_allocator);
    defer bindings_writer.deinit();
    try writeBindingsJson(&bindings_writer.writer, bindings);

    var buf: [65536]u8 = undefined;
    const n = op(
        binding_name.ptr,
        binding_name.len,
        sql.ptr,
        sql.len,
        bindings_writer.written().ptr,
        bindings_writer.written().len,
        &buf,
        buf.len,
    );
    if (n < 0) return error.DatabaseQueryFailed;
    if (n == 0) return &[_]db.Row{};

    const parsed = try std.json.parseFromSlice([]WireRow, allocator, buf[0..@intCast(n)], .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    return cloneRows(allocator, parsed.value);
}

fn selectValues(allocator: std.mem.Allocator, binding_name: []const u8, sql: []const u8, bindings: db.Bindings) ![]const []const db.Value {
    var bindings_writer = std.Io.Writer.Allocating.init(std.heap.wasm_allocator);
    defer bindings_writer.deinit();
    try writeBindingsJson(&bindings_writer.writer, bindings);

    var buf: [65536]u8 = undefined;
    const n = ext.db_values(
        binding_name.ptr,
        binding_name.len,
        sql.ptr,
        sql.len,
        bindings_writer.written().ptr,
        bindings_writer.written().len,
        &buf,
        buf.len,
    );
    if (n < 0) return error.DatabaseQueryFailed;
    if (n == 0) return &[_][]const db.Value{};

    const parsed = try std.json.parseFromSlice([][]WireValue, allocator, buf[0..@intCast(n)], .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    const rows = try allocator.alloc([]const db.Value, parsed.value.len);
    for (parsed.value, 0..) |wire_row, row_index| {
        const values_row = try allocator.alloc(db.Value, wire_row.len);
        for (wire_row, 0..) |wire_value, value_index| {
            values_row[value_index] = try cloneValue(allocator, wire_value);
        }
        rows[row_index] = values_row;
    }
    return rows;
}

fn cloneRows(allocator: std.mem.Allocator, wire_rows: []const WireRow) ![]const db.Row {
    const rows = try allocator.alloc(db.Row, wire_rows.len);
    for (wire_rows, 0..) |wire_row, row_index| {
        const fields = try allocator.alloc(db.Field, wire_row.fields.len);
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

fn cloneValue(allocator: std.mem.Allocator, wire_value: WireValue) !db.Value {
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

fn writeBindingsJson(writer: *std.Io.Writer, bindings: db.Bindings) !void {
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

fn writeValueJson(writer: *std.Io.Writer, value: db.Value) !void {
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

const database_vtable = db.Database.VTable{
    .query = &query,
    .prepare = &prepare,
    .run = &run,
    .transaction = &transaction,
    .close = &close,
    .serialize = &serialize,
    .load_extension = &loadExtension,
    .file_control = &fileControl,
    .native = &native,
};

const statement_vtable = db.Statement.VTable{
    .all = &all,
    .get = &get,
    .run = &runStatement,
    .values = &values,
    .iterate = &iterate,
    .finalize = &finalize,
    .to_string = &toString,
    .column_names = &columnNames,
    .column_types = &columnTypes,
    .declared_types = &declaredTypes,
    .params_count = &paramsCount,
    .native = &native,
};

const driver_vtable = db.DriverVTable{
    .open = &open,
    .deserialize = &deserialize,
};

var _ctx: u8 = 0;

pub fn use() void {
    db.adapter(@ptrCast(&_ctx), &driver_vtable);
}
