const std = @import("std");
const zx = @import("zx");

const db = zx.db;

test "db api: module surface compiles" {
    const options = db.OpenOptions{
        .readonly = true,
        .create = false,
        .readwrite = false,
        .safe_integers = true,
        .strict = true,
    };

    const value = db.Value{ .integer = 42 };
    const bindings = db.Bindings.fromPositional(&.{value});
    const named = db.Bindings.fromNamed(&.{.{ .name = "$id", .value = value }});

    _ = options;
    _ = bindings;
    _ = named;
    _ = db.open;
    _ = db.deserialize;
    _ = db.adapter;
    _ = db.Database.open;
    _ = db.Database.init;
    _ = db.Database.deserialize;
    _ = db.Database.query;
    _ = db.Database.prepare;
    _ = db.Database.run;
    _ = db.Database.exec;
    _ = db.Database.transaction;
    _ = db.Database.transactionDeferred;
    _ = db.Database.transactionImmediate;
    _ = db.Database.transactionExclusive;
    _ = db.Database.serialize;
    _ = db.Database.loadExtension;
    _ = db.Database.fileControl;
    _ = db.Database.close;
    _ = db.Statement.all;
    _ = db.Statement.get;
    _ = db.Statement.run;
    _ = db.Statement.values;
    _ = db.Statement.iterate;
    _ = db.Statement.finalize;
    _ = db.Statement.toString;
    _ = db.Statement.columnNames;
    _ = db.Statement.columnTypes;
    _ = db.Statement.declaredTypes;
    _ = db.Statement.paramsCount;

    if (true) return error.Todo;
}

test "db api: database behavior pending adapter implementation" {
    var database = try db.Database.open(null, .{});
    defer database.deinit();

    if (true) return error.Todo;
}

test "db api: statement behavior pending adapter implementation" {
    var database = try db.Database.open(null, .{});
    defer database.deinit();

    var statement = try database.query("select 1");
    defer statement.deinit();

    if (true) return error.Todo;
}
