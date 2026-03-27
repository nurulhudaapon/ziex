const std = @import("std");

const db = @import("../db.zig");

const DbError = db.DbError;
const RunResult = db.RunResult;
const Row = db.Row;
const Value = db.Value;
const ColumnType = db.ColumnType;
const FileControlValue = db.FileControlValue;
const TransactionMode = db.TransactionMode;
const TransactionCallback = db.TransactionCallback;
const Bindings = db.Bindings;
const OpenOptions = db.OpenOptions;
const Database = db.Database;
const Statement = db.Statement;

const empty_column_names = [_][]const u8{};
const empty_column_types = [_]ColumnType{};
const empty_declared_types = [_]?[]const u8{};

pub const vtable = db.DriverVTable{
    .open = &open,
    .deserialize = &deserialize,
};

const database_vtable = Database.VTable{
    .query = &query,
    .prepare = &prepare,
    .run = &runSql,
    .transaction = &transaction,
    .close = &close,
    .serialize = &serialize,
    .load_extension = &loadExtension,
    .file_control = &fileControl,
    .native = &native,
};

const statement_vtable = Statement.VTable{
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

var _stateless: u8 = 0;

fn open(_: *anyopaque, _: ?[]const u8, _: OpenOptions) anyerror!Database {
    return .{
        .backend_ctx = @ptrCast(&_stateless),
        .vtable = &database_vtable,
    };
}

fn deserialize(_: *anyopaque, _: []const u8, _: OpenOptions) anyerror!Database {
    return .{
        .backend_ctx = @ptrCast(&_stateless),
        .vtable = &database_vtable,
    };
}

fn query(_: *anyopaque, _: []const u8) anyerror!Statement {
    return .{
        .backend_ctx = @ptrCast(&_stateless),
        .vtable = &statement_vtable,
    };
}

fn prepare(_: *anyopaque, _: []const u8) anyerror!Statement {
    return .{
        .backend_ctx = @ptrCast(&_stateless),
        .vtable = &statement_vtable,
    };
}

fn runSql(_: *anyopaque, _: []const u8, _: Bindings) anyerror!RunResult {
    return DbError.Unimplemented;
}

fn transaction(_: *anyopaque, _: TransactionMode, _: *anyopaque, _: TransactionCallback) anyerror!void {
    return DbError.Unimplemented;
}

fn close(_: *anyopaque, _: bool) anyerror!void {}

fn serialize(_: *anyopaque, _: std.mem.Allocator) anyerror![]u8 {
    return DbError.Unimplemented;
}

fn loadExtension(_: *anyopaque, _: []const u8, _: ?[]const u8) anyerror!void {
    return DbError.Unimplemented;
}

fn fileControl(_: *anyopaque, _: i32, _: FileControlValue) anyerror!void {
    return DbError.Unimplemented;
}

fn native(_: *anyopaque) ?*anyopaque {
    return null;
}

fn all(_: *anyopaque, _: std.mem.Allocator, _: Bindings) anyerror![]const Row {
    return DbError.Unimplemented;
}

fn get(_: *anyopaque, _: std.mem.Allocator, _: Bindings) anyerror!?Row {
    return DbError.Unimplemented;
}

fn runStatement(_: *anyopaque, _: Bindings) anyerror!RunResult {
    return DbError.Unimplemented;
}

fn values(_: *anyopaque, _: std.mem.Allocator, _: Bindings) anyerror![]const []const Value {
    return DbError.Unimplemented;
}

fn iterate(_: *anyopaque, _: Bindings) anyerror!Statement.Iterator {
    return .{};
}

fn finalize(_: *anyopaque) void {}

fn toString(_: *anyopaque, allocator: std.mem.Allocator) anyerror![]u8 {
    return allocator.dupe(u8, "");
}

fn columnNames(_: *anyopaque) []const []const u8 {
    return empty_column_names[0..];
}

fn columnTypes(_: *anyopaque) []const ColumnType {
    return empty_column_types[0..];
}

fn declaredTypes(_: *anyopaque) []const ?[]const u8 {
    return empty_declared_types[0..];
}

fn paramsCount(_: *anyopaque) usize {
    return 0;
}
