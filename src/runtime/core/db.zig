//! Backend-agnostic database abstraction inspired by Bun's `bun:sqlite` API.
//!
//! This module intentionally defines API shape and dispatch only. Concrete
//! database behavior is supplied by platform adapters via vtables.

const std = @import("std");

pub const Driver = @This();

pub const DbError = error{
    Unimplemented,
    Closed,
    Busy,
    InvalidQuery,
    InvalidBindings,
    InvalidState,
    Unsupported,
};

pub const OpenOptions = struct {
    readonly: bool = false,
    create: bool = false,
    readwrite: bool = true,
    safe_integers: bool = false,
    strict: bool = false,
};

pub const TransactionMode = enum {
    deferred,
    immediate,
    exclusive,
};

pub const ColumnType = enum {
    integer,
    float,
    text,
    blob,
    null,
    unknown,
};

pub const Value = union(enum) {
    null,
    integer: i64,
    float: f64,
    text: []const u8,
    blob: []const u8,
    boolean: bool,
};

pub const Field = struct {
    name: []const u8,
    value: Value,
};

pub const Row = struct {
    fields: []const Field,

    pub fn get(self: Row, name: []const u8) ?Value {
        for (self.fields) |field| {
            if (std.mem.eql(u8, field.name, name)) return field.value;
        }
        return null;
    }
};

pub const NamedBinding = struct {
    name: []const u8,
    value: Value,
};

pub const Bindings = union(enum) {
    none,
    positional: []const Value,
    named: []const NamedBinding,

    pub const empty: Bindings = .{ .none = {} };

    pub fn fromPositional(values: []const Value) Bindings {
        return .{ .positional = values };
    }

    pub fn fromNamed(values: []const NamedBinding) Bindings {
        return .{ .named = values };
    }
};

pub const RunResult = struct {
    last_insert_rowid: i64 = 0,
    changes: usize = 0,
};

pub const FileControlValue = union(enum) {
    none,
    integer: i64,
    bytes: []u8,
    const_bytes: []const u8,
};

pub const TransactionCallback = *const fn (ctx: *anyopaque, db: *Database) anyerror!void;

pub const DriverVTable = struct {
    open: *const fn (ctx: *anyopaque, filename: ?[]const u8, options: OpenOptions) anyerror!Database,
    deserialize: *const fn (ctx: *anyopaque, bytes: []const u8, options: OpenOptions) anyerror!Database,
};

var _stateless: u8 = 0;
var _ctx: *anyopaque = @ptrCast(&_stateless);
var _vtable: *const DriverVTable = &noop_driver_vtable;

/// Override the active database backend. Called once at startup by platform adapters.
pub fn impl(ctx: *anyopaque, vtable: *const DriverVTable) void {
    _ctx = ctx;
    _vtable = vtable;
}

/// Open or create a database connection.
pub fn open(filename: ?[]const u8, options: OpenOptions) !Database {
    return _vtable.open(_ctx, filename, options);
}

/// Create a database from serialized bytes.
pub fn deserialize(bytes: []const u8, options: OpenOptions) !Database {
    return _vtable.deserialize(_ctx, bytes, options);
}

/// Bun-like database handle with adapter-provided behavior.
pub const Database = struct {
    backend_ctx: ?*anyopaque = null,
    vtable: ?*const VTable = null,

    pub const VTable = struct {
        query: *const fn (ctx: *anyopaque, sql: []const u8) anyerror!Statement,
        prepare: *const fn (ctx: *anyopaque, sql: []const u8) anyerror!Statement,
        run: *const fn (ctx: *anyopaque, sql: []const u8, bindings: Bindings) anyerror!RunResult,
        transaction: *const fn (ctx: *anyopaque, mode: TransactionMode, callback_ctx: *anyopaque, callback: TransactionCallback) anyerror!void,
        close: *const fn (ctx: *anyopaque, throw_on_error: bool) anyerror!void,
        serialize: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) anyerror![]u8,
        load_extension: *const fn (ctx: *anyopaque, name: []const u8, entry_point: ?[]const u8) anyerror!void,
        file_control: *const fn (ctx: *anyopaque, cmd: i32, value: FileControlValue) anyerror!void,
        native: *const fn (ctx: *anyopaque) ?*anyopaque,
    };

    pub fn open(filename: ?[]const u8, options: OpenOptions) !Database {
        return Driver.open(filename, options);
    }

    pub fn init(filename: ?[]const u8, options: OpenOptions) !Database {
        return Driver.open(filename, options);
    }

    pub fn deserialize(bytes: []const u8, options: OpenOptions) !Database {
        return Driver.deserialize(bytes, options);
    }

    pub fn query(self: *Database, sql: []const u8) !Statement {
        const ctx = try self.requireCtx();
        const vt = try self.requireVTable();
        return vt.query(ctx, sql);
    }

    pub fn prepare(self: *Database, sql: []const u8) !Statement {
        const ctx = try self.requireCtx();
        const vt = try self.requireVTable();
        return vt.prepare(ctx, sql);
    }

    pub fn run(self: *Database, sql: []const u8, bindings: Bindings) !RunResult {
        const ctx = try self.requireCtx();
        const vt = try self.requireVTable();
        return vt.run(ctx, sql, bindings);
    }

    pub fn exec(self: *Database, sql: []const u8, bindings: Bindings) !RunResult {
        return self.run(sql, bindings);
    }

    pub fn transaction(self: *Database, callback_ctx: *anyopaque, callback: TransactionCallback) !void {
        return self.transactionMode(.deferred, callback_ctx, callback);
    }

    pub fn transactionDeferred(self: *Database, callback_ctx: *anyopaque, callback: TransactionCallback) !void {
        return self.transactionMode(.deferred, callback_ctx, callback);
    }

    pub fn transactionImmediate(self: *Database, callback_ctx: *anyopaque, callback: TransactionCallback) !void {
        return self.transactionMode(.immediate, callback_ctx, callback);
    }

    pub fn transactionExclusive(self: *Database, callback_ctx: *anyopaque, callback: TransactionCallback) !void {
        return self.transactionMode(.exclusive, callback_ctx, callback);
    }

    pub fn serialize(self: *Database, allocator: std.mem.Allocator) ![]u8 {
        const ctx = try self.requireCtx();
        const vt = try self.requireVTable();
        return vt.serialize(ctx, allocator);
    }

    pub fn loadExtension(self: *Database, name: []const u8, entry_point: ?[]const u8) !void {
        const ctx = try self.requireCtx();
        const vt = try self.requireVTable();
        return vt.load_extension(ctx, name, entry_point);
    }

    pub fn fileControl(self: *Database, cmd: i32, value: FileControlValue) !void {
        const ctx = try self.requireCtx();
        const vt = try self.requireVTable();
        return vt.file_control(ctx, cmd, value);
    }

    pub fn native(self: *Database) ?*anyopaque {
        const ctx = self.backend_ctx orelse return null;
        const vt = self.vtable orelse return null;
        return vt.native(ctx);
    }

    pub fn close(self: *Database, throw_on_error: bool) !void {
        const ctx = try self.requireCtx();
        const vt = try self.requireVTable();
        defer {
            self.backend_ctx = null;
            self.vtable = null;
        }
        return vt.close(ctx, throw_on_error);
    }

    pub fn deinit(self: *Database) void {
        self.close(false) catch {};
    }

    fn transactionMode(self: *Database, mode: TransactionMode, callback_ctx: *anyopaque, callback: TransactionCallback) !void {
        const ctx = try self.requireCtx();
        const vt = try self.requireVTable();
        return vt.transaction(ctx, mode, callback_ctx, callback);
    }

    fn requireCtx(self: *Database) !*anyopaque {
        return self.backend_ctx orelse DbError.Closed;
    }

    fn requireVTable(self: *Database) !*const VTable {
        return self.vtable orelse DbError.Closed;
    }
};

pub const Statement = struct {
    backend_ctx: ?*anyopaque = null,
    vtable: ?*const VTable = null,

    pub const Iterator = struct {
        backend_ctx: ?*anyopaque = null,
        next_fn: ?*const fn (ctx: *anyopaque) anyerror!?Row = null,
        deinit_fn: ?*const fn (ctx: *anyopaque) void = null,

        pub fn next(self: *Iterator) !?Row {
            const ctx = self.backend_ctx orelse return null;
            const next_fn = self.next_fn orelse return null;
            return next_fn(ctx);
        }

        pub fn deinit(self: *Iterator) void {
            const ctx = self.backend_ctx orelse return;
            const deinit_fn = self.deinit_fn orelse return;
            deinit_fn(ctx);
            self.backend_ctx = null;
            self.next_fn = null;
            self.deinit_fn = null;
        }
    };

    pub const VTable = struct {
        all: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, bindings: Bindings) anyerror![]const Row,
        get: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, bindings: Bindings) anyerror!?Row,
        run: *const fn (ctx: *anyopaque, bindings: Bindings) anyerror!RunResult,
        values: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, bindings: Bindings) anyerror![]const []const Value,
        iterate: *const fn (ctx: *anyopaque, bindings: Bindings) anyerror!Iterator,
        finalize: *const fn (ctx: *anyopaque) void,
        to_string: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) anyerror![]u8,
        column_names: *const fn (ctx: *anyopaque) []const []const u8,
        column_types: *const fn (ctx: *anyopaque) []const ColumnType,
        declared_types: *const fn (ctx: *anyopaque) []const ?[]const u8,
        params_count: *const fn (ctx: *anyopaque) usize,
        native: *const fn (ctx: *anyopaque) ?*anyopaque,
    };

    pub fn all(self: *Statement, allocator: std.mem.Allocator, bindings: Bindings) ![]const Row {
        const ctx = try self.requireCtx();
        const vt = try self.requireVTable();
        return vt.all(ctx, allocator, bindings);
    }

    pub fn get(self: *Statement, allocator: std.mem.Allocator, bindings: Bindings) !?Row {
        const ctx = try self.requireCtx();
        const vt = try self.requireVTable();
        return vt.get(ctx, allocator, bindings);
    }

    pub fn run(self: *Statement, bindings: Bindings) !RunResult {
        const ctx = try self.requireCtx();
        const vt = try self.requireVTable();
        return vt.run(ctx, bindings);
    }

    pub fn values(self: *Statement, allocator: std.mem.Allocator, bindings: Bindings) ![]const []const Value {
        const ctx = try self.requireCtx();
        const vt = try self.requireVTable();
        return vt.values(ctx, allocator, bindings);
    }

    pub fn iterate(self: *Statement, bindings: Bindings) !Iterator {
        const ctx = try self.requireCtx();
        const vt = try self.requireVTable();
        return vt.iterate(ctx, bindings);
    }

    pub fn finalize(self: *Statement) void {
        const ctx = self.backend_ctx orelse return;
        const vt = self.vtable orelse return;
        vt.finalize(ctx);
        self.backend_ctx = null;
        self.vtable = null;
    }

    pub fn deinit(self: *Statement) void {
        self.finalize();
    }

    pub fn toString(self: *Statement, allocator: std.mem.Allocator) ![]u8 {
        const ctx = try self.requireCtx();
        const vt = try self.requireVTable();
        return vt.to_string(ctx, allocator);
    }

    pub fn columnNames(self: *Statement) ![]const []const u8 {
        const ctx = try self.requireCtx();
        const vt = try self.requireVTable();
        return vt.column_names(ctx);
    }

    pub fn columnTypes(self: *Statement) ![]const ColumnType {
        const ctx = try self.requireCtx();
        const vt = try self.requireVTable();
        return vt.column_types(ctx);
    }

    pub fn declaredTypes(self: *Statement) ![]const ?[]const u8 {
        const ctx = try self.requireCtx();
        const vt = try self.requireVTable();
        return vt.declared_types(ctx);
    }

    pub fn paramsCount(self: *Statement) !usize {
        const ctx = try self.requireCtx();
        const vt = try self.requireVTable();
        return vt.params_count(ctx);
    }

    pub fn native(self: *Statement) ?*anyopaque {
        const ctx = self.backend_ctx orelse return null;
        const vt = self.vtable orelse return null;
        return vt.native(ctx);
    }

    fn requireCtx(self: *Statement) !*anyopaque {
        return self.backend_ctx orelse DbError.Closed;
    }

    fn requireVTable(self: *Statement) !*const VTable {
        return self.vtable orelse DbError.Closed;
    }
};

const empty_fields = [_]Field{};
const empty_rows = [_]Row{};
const empty_values = [_]Value{};
const empty_value_rows = [_][]const Value{};
const empty_column_names = [_][]const u8{};
const empty_column_types = [_]ColumnType{};
const empty_declared_types = [_]?[]const u8{};

fn noopOpen(_: *anyopaque, _: ?[]const u8, _: OpenOptions) anyerror!Database {
    return .{
        .backend_ctx = @ptrCast(&_stateless),
        .vtable = &noop_database_vtable,
    };
}

fn noopDeserialize(_: *anyopaque, _: []const u8, _: OpenOptions) anyerror!Database {
    return .{
        .backend_ctx = @ptrCast(&_stateless),
        .vtable = &noop_database_vtable,
    };
}

fn noopQuery(_: *anyopaque, _: []const u8) anyerror!Statement {
    return .{
        .backend_ctx = @ptrCast(&_stateless),
        .vtable = &noop_statement_vtable,
    };
}

fn noopPrepare(_: *anyopaque, _: []const u8) anyerror!Statement {
    return .{
        .backend_ctx = @ptrCast(&_stateless),
        .vtable = &noop_statement_vtable,
    };
}

fn noopRunSql(_: *anyopaque, _: []const u8, _: Bindings) anyerror!RunResult {
    return DbError.Unimplemented;
}

fn noopTransaction(_: *anyopaque, _: TransactionMode, _: *anyopaque, _: TransactionCallback) anyerror!void {
    return DbError.Unimplemented;
}

fn noopClose(_: *anyopaque, _: bool) anyerror!void {}

fn noopSerialize(_: *anyopaque, _: std.mem.Allocator) anyerror![]u8 {
    return DbError.Unimplemented;
}

fn noopLoadExtension(_: *anyopaque, _: []const u8, _: ?[]const u8) anyerror!void {
    return DbError.Unimplemented;
}

fn noopFileControl(_: *anyopaque, _: i32, _: FileControlValue) anyerror!void {
    return DbError.Unimplemented;
}

fn noopNative(_: *anyopaque) ?*anyopaque {
    return null;
}

fn noopAll(_: *anyopaque, _: std.mem.Allocator, _: Bindings) anyerror![]const Row {
    return DbError.Unimplemented;
}

fn noopGet(_: *anyopaque, _: std.mem.Allocator, _: Bindings) anyerror!?Row {
    return DbError.Unimplemented;
}

fn noopRunStatement(_: *anyopaque, _: Bindings) anyerror!RunResult {
    return DbError.Unimplemented;
}

fn noopValues(_: *anyopaque, _: std.mem.Allocator, _: Bindings) anyerror![]const []const Value {
    return DbError.Unimplemented;
}

fn noopIterate(_: *anyopaque, _: Bindings) anyerror!Statement.Iterator {
    return .{};
}

fn noopFinalize(_: *anyopaque) void {}

fn noopToString(_: *anyopaque, allocator: std.mem.Allocator) anyerror![]u8 {
    return allocator.dupe(u8, "");
}

fn noopColumnNames(_: *anyopaque) []const []const u8 {
    return empty_column_names[0..];
}

fn noopColumnTypes(_: *anyopaque) []const ColumnType {
    return empty_column_types[0..];
}

fn noopDeclaredTypes(_: *anyopaque) []const ?[]const u8 {
    return empty_declared_types[0..];
}

fn noopParamsCount(_: *anyopaque) usize {
    return 0;
}

const noop_driver_vtable = DriverVTable{
    .open = &noopOpen,
    .deserialize = &noopDeserialize,
};

const noop_database_vtable = Database.VTable{
    .query = &noopQuery,
    .prepare = &noopPrepare,
    .run = &noopRunSql,
    .transaction = &noopTransaction,
    .close = &noopClose,
    .serialize = &noopSerialize,
    .load_extension = &noopLoadExtension,
    .file_control = &noopFileControl,
    .native = &noopNative,
};

const noop_statement_vtable = Statement.VTable{
    .all = &noopAll,
    .get = &noopGet,
    .run = &noopRunStatement,
    .values = &noopValues,
    .iterate = &noopIterate,
    .finalize = &noopFinalize,
    .to_string = &noopToString,
    .column_names = &noopColumnNames,
    .column_types = &noopColumnTypes,
    .declared_types = &noopDeclaredTypes,
    .params_count = &noopParamsCount,
    .native = &noopNative,
};
