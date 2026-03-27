const std = @import("std");
const zx = @import("zx");

const db = zx.db;
var next_db_id: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);

test "db tests:beforeAll" {
    zx.server.db.use();
}

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
    _ = db.configure;
    _ = db.setDefaultUrl;
    _ = db.setDefaultOptions;
    _ = db.connection;
    _ = db.closeDefault;
    _ = db.query;
    _ = db.prepare;
    _ = db.run;
    _ = db.exec;
    _ = db.transaction;
    _ = db.transactionDeferred;
    _ = db.transactionImmediate;
    _ = db.transactionExclusive;
    _ = db.serializeDefault;
    _ = db.Connection.open;
    _ = db.Connection.init;
    _ = db.Connection.deserialize;
    _ = db.Connection.query;
    _ = db.Connection.prepare;
    _ = db.Connection.run;
    _ = db.Connection.exec;
    _ = db.Connection.transaction;
    _ = db.Connection.transactionDeferred;
    _ = db.Connection.transactionImmediate;
    _ = db.Connection.transactionExclusive;
    _ = db.Connection.serialize;
    _ = db.Connection.loadExtension;
    _ = db.Connection.fileControl;
    _ = db.Connection.close;
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
}

test "db api: database open and run" {
    var database = try openTestDatabase();
    defer database.deinit();

    const create_result = try database.run(
        \\CREATE TABLE users (
        \\  id INTEGER PRIMARY KEY,
        \\  name TEXT NOT NULL,
        \\  score REAL NOT NULL
        \\)
    , .empty);
    try std.testing.expectEqual(@as(usize, 0), create_result.changes);

    const insert_result = try database.exec(
        "INSERT INTO users (name, score) VALUES (?1, ?2)",
        db.Bindings.fromPositional(&.{
            .{ .text = "Ada" },
            .{ .float = 9.5 },
        }),
    );
    try std.testing.expectEqual(@as(usize, 1), insert_result.changes);
    try std.testing.expect(insert_result.last_insert_rowid > 0);
}

test "db api: statement get/all/values and metadata" {
    var database = try openSeededDatabase();
    defer database.deinit();

    var statement = try database.prepare(
        \\SELECT id, name, score
        \\FROM users
        \\WHERE name = $name
        \\ORDER BY id
    );
    defer statement.deinit();

    try std.testing.expectEqual(@as(usize, 1), try statement.paramsCount());

    const column_names = try statement.columnNames();
    try std.testing.expectEqual(@as(usize, 3), column_names.len);
    try std.testing.expectEqualStrings("id", column_names[0]);
    try std.testing.expectEqualStrings("name", column_names[1]);
    try std.testing.expectEqualStrings("score", column_names[2]);

    const declared_types = try statement.declaredTypes();
    try std.testing.expectEqual(@as(usize, 3), declared_types.len);
    try std.testing.expectEqualStrings("INTEGER", declared_types[0].?);
    try std.testing.expectEqualStrings("TEXT", declared_types[1].?);
    try std.testing.expectEqualStrings("REAL", declared_types[2].?);

    const column_types = try statement.columnTypes();
    try std.testing.expectEqual(@as(usize, 3), column_types.len);
    try std.testing.expectEqual(.integer, column_types[0]);
    try std.testing.expectEqual(.text, column_types[1]);
    try std.testing.expectEqual(.float, column_types[2]);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const named_bindings = db.Bindings.fromNamed(&.{
        .{ .name = "$name", .value = .{ .text = "Ada" } },
    });

    const row = (try statement.get(alloc, named_bindings)).?;
    try expectIntField(row, "id", 1);
    try expectTextField(row, "name", "Ada");
    try expectFloatField(row, "score", 9.5);

    const all_rows = try statement.all(alloc, named_bindings);
    try std.testing.expectEqual(@as(usize, 1), all_rows.len);
    try expectTextField(all_rows[0], "name", "Ada");

    const values_rows = try statement.values(alloc, named_bindings);
    try std.testing.expectEqual(@as(usize, 1), values_rows.len);
    try std.testing.expectEqual(@as(usize, 3), values_rows[0].len);
    try std.testing.expectEqual(@as(i64, 1), expectInteger(values_rows[0][0]));
    try std.testing.expectEqualStrings("Ada", expectText(values_rows[0][1]));
}

test "db api: statement run with named bindings" {
    var database = try openTestDatabase();
    defer database.deinit();

    _ = try database.run(
        \\CREATE TABLE users (
        \\  id INTEGER PRIMARY KEY,
        \\  name TEXT NOT NULL,
        \\  score REAL NOT NULL
        \\)
    , .empty);

    var statement = try database.prepare("INSERT INTO users (name, score) VALUES ($name, $score)");
    defer statement.deinit();

    const result = try statement.run(db.Bindings.fromNamed(&.{
        .{ .name = "$name", .value = .{ .text = "Grace" } },
        .{ .name = "$score", .value = .{ .float = 8.25 } },
    }));
    try std.testing.expectEqual(@as(usize, 1), result.changes);

    var verify = try database.query("SELECT COUNT(*) AS total FROM users WHERE name = 'Grace'");
    defer verify.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const row = (try verify.get(arena.allocator(), .empty)).?;
    try expectIntField(row, "total", 1);
}

test "db api: transaction commit and rollback" {
    var database = try openTestDatabase();
    defer database.deinit();

    _ = try database.run(
        \\CREATE TABLE users (
        \\  id INTEGER PRIMARY KEY,
        \\  name TEXT NOT NULL,
        \\  score REAL NOT NULL
        \\)
    , .empty);

    try database.transactionImmediate(@ptrCast(&database), &insertCommittedUser);
    try std.testing.expectEqual(@as(i64, 1), try countUsers(&database));

    const rollback_result = database.transactionExclusive(@ptrCast(&database), &insertThenFail);
    try std.testing.expectError(error.ExpectedRollback, rollback_result);
    try std.testing.expectEqual(@as(i64, 1), try countUsers(&database));
}

test "db api: file url persists across reopen" {
    const url = try makeTestDatabaseUrl(std.testing.allocator);
    defer freeTestDatabaseUrl(std.testing.allocator, url);

    {
        var database = try db.open(url, .{});
        defer database.deinit();

        _ = try database.run(
            \\CREATE TABLE visits (
            \\  id INTEGER PRIMARY KEY,
            \\  note TEXT NOT NULL
            \\)
        , .empty);

        _ = try database.run(
            "INSERT INTO visits (note) VALUES (?1)",
            db.Bindings.fromPositional(&.{.{ .text = "first" }}),
        );
    }

    {
        var database = try db.open(url, .{});
        defer database.deinit();

        var statement = try database.query("SELECT COUNT(*) AS total FROM visits");
        defer statement.deinit();

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        const row = (try statement.get(arena.allocator(), .empty)).?;
        try expectIntField(row, "total", 1);
    }
}

test "db api: implicit default connection helpers" {
    const url = try makeTestDatabaseUrl(std.testing.allocator);
    defer freeTestDatabaseUrl(std.testing.allocator, url);
    defer db.closeDefault();

    db.setDefaultUrl(url);
    db.setDefaultOptions(.{ .max_pool_size = 2 });

    _ = try db.run(
        \\CREATE TABLE visits (
        \\  id INTEGER PRIMARY KEY,
        \\  note TEXT NOT NULL
        \\)
    , .empty);

    _ = try db.exec(
        "INSERT INTO visits (note) VALUES (?1)",
        db.Bindings.fromPositional(&.{.{ .text = "hello" }}),
    );

    var statement = try db.query("SELECT COUNT(*) AS total FROM visits");
    defer statement.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const row = (try statement.get(arena.allocator(), .empty)).?;
    try expectIntField(row, "total", 1);
}

test "db api: implicit default scope covers prepare exec and connection reuse" {
    const url = try makeTestDatabaseUrl(std.testing.allocator);
    defer freeTestDatabaseUrl(std.testing.allocator, url);
    defer db.closeDefault();

    db.setDefaultUrl(url);
    db.setDefaultOptions(.{ .max_pool_size = 2 });

    const conn_a = try db.connection();
    const conn_b = try db.connection();
    try std.testing.expect(conn_a == conn_b);

    _ = try db.run(
        \\CREATE TABLE notes (
        \\  id INTEGER PRIMARY KEY,
        \\  body TEXT NOT NULL
        \\)
    , .empty);

    var insert = try db.prepare("INSERT INTO notes (body) VALUES ($body)");
    defer insert.deinit();

    _ = try insert.run(db.Bindings.fromNamed(&.{
        .{ .name = "$body", .value = .{ .text = "first" } },
    }));

    _ = try db.exec(
        "INSERT INTO notes (body) VALUES (?1)",
        db.Bindings.fromPositional(&.{.{ .text = "second" }}),
    );

    var statement = try db.query("SELECT id, body FROM notes ORDER BY id");
    defer statement.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const rows = try statement.all(arena.allocator(), .empty);
    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try expectTextField(rows[0], "body", "first");
    try expectTextField(rows[1], "body", "second");
}

fn openTestDatabase() !db.Connection {
    return db.open("mem://", .{});
}

fn openSeededDatabase() !db.Connection {
    var database = try openTestDatabase();
    errdefer database.deinit();

    _ = try database.run(
        \\CREATE TABLE users (
        \\  id INTEGER PRIMARY KEY,
        \\  name TEXT NOT NULL,
        \\  score REAL NOT NULL
        \\)
    , .empty);

    _ = try database.run(
        \\INSERT INTO users (name, score) VALUES
        \\  (?1, ?2),
        \\  (?3, ?4)
    , db.Bindings.fromPositional(&.{
        .{ .text = "Ada" },
        .{ .float = 9.5 },
        .{ .text = "Grace" },
        .{ .float = 8.25 },
    }));

    return database;
}

fn countUsers(database: *db.Connection) !i64 {
    var statement = try database.query("SELECT COUNT(*) AS total FROM users");
    defer statement.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const row = (try statement.get(arena.allocator(), .empty)).?;
    return expectInteger(row.get("total") orelse .null);
}

fn insertCommittedUser(ctx: *anyopaque, database: *db.Connection) !void {
    _ = ctx;
    _ = try database.run(
        "INSERT INTO users (name, score) VALUES (?1, ?2)",
        db.Bindings.fromPositional(&.{
            .{ .text = "Committed" },
            .{ .float = 10.0 },
        }),
    );
}

fn insertThenFail(ctx: *anyopaque, database: *db.Connection) !void {
    _ = ctx;
    _ = try database.run(
        "INSERT INTO users (name, score) VALUES (?1, ?2)",
        db.Bindings.fromPositional(&.{
            .{ .text = "Rolled Back" },
            .{ .float = 1.0 },
        }),
    );
    return error.ExpectedRollback;
}

fn expectIntField(row: db.Row, name: []const u8, expected: i64) !void {
    try std.testing.expectEqual(expected, expectInteger(row.get(name) orelse .null));
}

fn expectFloatField(row: db.Row, name: []const u8, expected: f64) !void {
    switch (row.get(name) orelse .null) {
        .float => |value| try std.testing.expectApproxEqAbs(expected, value, 0.0001),
        .integer => |value| try std.testing.expectApproxEqAbs(expected, @as(f64, @floatFromInt(value)), 0.0001),
        else => return error.UnexpectedValueType,
    }
}

fn expectTextField(row: db.Row, name: []const u8, expected: []const u8) !void {
    try std.testing.expectEqualStrings(expected, expectText(row.get(name) orelse .null));
}

fn expectInteger(value: db.Value) i64 {
    return switch (value) {
        .integer => |v| v,
        .float => |v| @intFromFloat(v),
        else => unreachable,
    };
}

fn expectText(value: db.Value) []const u8 {
    return switch (value) {
        .text => |v| v,
        else => unreachable,
    };
}

fn makeTestDatabaseUrl(allocator: std.mem.Allocator) ![]const u8 {
    const id = next_db_id.fetchAdd(1, .monotonic);
    const url = try std.fmt.allocPrint(allocator, "file:/tmp/ziex-db-test-{d}.sqlite", .{id});
    errdefer allocator.free(url);

    try cleanupDatabaseFiles(filePathFromUrl(url));

    return url;
}

fn freeTestDatabaseUrl(allocator: std.mem.Allocator, url: []const u8) void {
    cleanupDatabaseFiles(filePathFromUrl(url)) catch {};
    allocator.free(url);
}

fn filePathFromUrl(url: []const u8) []const u8 {
    if (std.mem.startsWith(u8, url, "file:")) return url["file:".len..];
    return url;
}

fn cleanupDatabaseFiles(path: []const u8) !void {
    try deleteIfExists(path);

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    try deleteIfExists(try std.fmt.bufPrint(&buf, "{s}-wal", .{path}));
    try deleteIfExists(try std.fmt.bufPrint(&buf, "{s}-shm", .{path}));
    try deleteIfExists(try std.fmt.bufPrint(&buf, "{s}-journal", .{path}));
}

fn deleteIfExists(path: []const u8) !void {
    std.fs.deleteFileAbsolute(path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
}
