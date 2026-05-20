# A thin SQLite wrapper for Zig

## Zig Version
This is for Zig 0.16.0. Use the [zig-0.15.2](https://github.com/karlseguin/zqlite.zig/tree/zig-0.15.2) branch for Zig 0.15.2 or the [dev](https://github.com/karlseguin/zqlite.zig/tree/dev) which may or may not be up to date with zig dev.

## Example

```zig
// good idea to pass EXResCode to get extended result codes (more detailed error codes)
const flags =  zqlite.OpenFlags.Create | zqlite.OpenFlags.EXResCode;
var conn = try zqlite.open("/tmp/test.sqlite", flags);
defer conn.close();

try conn.exec("create table if not exists test (name text)", .{});
try conn.exec("insert into test (name) values (?1), (?2)", .{"Leto", "Ghanima"});

{
    if (try conn.row("select * from test order by name limit 1", .{})) |row| {
      defer row.deinit();
      std.debug.print("name: {s}\n", .{row.text(0)});
    }
}

{
    var rows = try conn.rows("select * from test order by name", .{});
    defer rows.deinit();
    while (rows.next()) |row| {
        std.debug.print("name: {s}\n", .{row.text(0)});
    }
    if (rows.err) |err| return err;
}
```

Unless `zqlite.OpenFlags.ReadOnly` is set in the open flags, `zqlite.OpenFlags.ReadWrite` is assumed (in other words, the database opens in read-write by default, and the `ReadOnly` flag must be used to open it in readony mode.)

## Install
This library is tested with SQLite3 3.53.0.

1) Add zqlite as a dependency in your `build.zig.zon`:

```bash
zig fetch --save git+https://github.com/karlseguin/zqlite.zig#master
```

2)  The library doesn't attempt to link/include SQLite. You're free to do this how you want.

If you have sqlite3 installed on your system you might get away with just adding this to your build.zig

```zig
const zqlite = b.dependency("zqlite", .{
    .target = target,
    .optimize = optimize,
});

exe.linkLibC();
exe.linkSystemLibrary("sqlite3");
exe.root_module.addImport("zqlite", zqlite.module("zqlite"));
```

Alternatively, If you download the SQLite amalgamation from [the SQLite download page](https://www.sqlite.org/download.html) and place the `sqlite.c` and `sqlite.h` file in your project's `lib/` folder, you can then:

2) Add this in `build.zig`:
```zig
const zqlite = b.dependency("zqlite", .{
    .target = target,
    .optimize = optimize,
});
exe.addCSourceFile(.{
    .file = b.path("lib/sqlite3.c"),
    .flags = &[_][]const u8{
        "-DSQLITE_DQS=0",
        "-DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1",
        "-DSQLITE_USE_ALLOCA=1",
        "-DSQLITE_THREADSAFE=1",
        "-DSQLITE_TEMP_STORE=3",
        "-DSQLITE_ENABLE_API_ARMOR=1",
        "-DSQLITE_ENABLE_UNLOCK_NOTIFY",
        "-DSQLITE_DEFAULT_FILE_PERMISSIONS=0600",
        "-DSQLITE_OMIT_DECLTYPE=1",
        "-DSQLITE_OMIT_DEPRECATED=1",
        "-DSQLITE_OMIT_LOAD_EXTENSION=1",
        "-DSQLITE_OMIT_PROGRESS_CALLBACK=1",
        "-DSQLITE_OMIT_SHARED_CACHE",
        "-DSQLITE_OMIT_TRACE=1",
        "-DSQLITE_OMIT_UTF16=1",
        "-DHAVE_USLEEP=0",
    },
});
exe.linkLibC();
exe.root_module.addImport("zqlite", zqlite.module("zqlite"));
```

You can tweak the SQLite build flags for your own needs/platform.

# Conn
The `Conn` type returned by `open` has the following functions:

* `row(sql, args) !?zqlite.Row` - returns an optional row
* `rows(sql, args) !zqlite.Rows` - returns an iterator that yields rows
* `exec(sql, args) !void` - executes *one* statement,
* `execNoArgs(sql) !void` - executes one or more statements, `sql` must be a null-terminated string
* `changes() usize` - the number of rows inserted/updated/deleted by the previous statement
* `lastInsertedRowId() i64` - the row id of the last inserted row
* `lastError() [*:0]const u8` - an error string describing the last error
* `transaction() !void` and `exclusiveTransaction() !void` - begins a transaction
* `commit() !void` and `rollback() void` - commits and rollback the current transaction
* `prepare(sql, args) !zqlite.Stmt` - returns a thin wrapper around a `*c.sqlite3_stmt`. `row` and `rows` wrap this type.
* `close() void` and `tryClose() !void` - closes the database. `close()` silently ignores any error, if you care about the error, use `tryClose()`
* `busyTimeout(ms)` - Sets the busyHandler for the connection. See https://www.sqlite.org/c3ref/busy_timeout.html

# Row and Rows
Both `row` and `rows` wrap an `zqlite.Stmt` which itself is a thin wrapper around an `*c.sqlite3_stmt`.

While `zqlite.Row` exposes a `deinit` and `deinitErr` method, it should only be called when the row was fetched directly from `conn.row(...)`:

```zig
if (try conn.row("select 1", .{})) |row| {
    defer row.deinit();  // must be called
    std.debug.print("{d}\n", .{row.int(0)});
}
```

When the `row` comes from iterating `rows`, `deinit` or `deinitErr` should not be called on the individual row:

```zig
var rows = try conn.rows("select 1 union all select 2", .{})
defer rows.deinit();  // must be called

while (rows.next()) |row| {
    // row.deinit() should not be called!
    ...
}
```

Note that `zqlite.Rows` has an `err: ?anyerror` field which can be checked at any point. Calls to `next()` when `err != null` will return null. Thus, `err` need only be checked at the end of the loop:

```zig
var rows = try conn.rows("select 1 union all select 2", .{})
defer rows.deinit();  // must be called

while (rows.next()) |row| {
    ...
}

if (rows.err) |err| {
    // something went wrong
}
```

## Row Getters
There are two APIs for fetching column data. The first is the generic `get`:

```zig
get(T, index) T
```
Where `T` can be: `i64`, 'f64', 'bool', '[]const u8', '[:0]const u8' or `zqlite.Blob` or their nullable equivalent (i.e. `?i64`). The return type for `zqlite.Blob` is `[]const u8`.

Alternatively, the following can be used:

* `boolean(index) bool`
* `nullableBoolean(index) ?bool`
* `int(index) i64`
* `nullableInt(index) ?i64`
* `float(index) f64`
* `nullableFloat(index) ?f64`
* `text(index) []const u8`
* `nullableText(index) ?[]const u8`
* `cString(index) [:0]const u8`
* `nullableCString(index) ?[:0]const u8`
* `blob(index) []const u8`
* `nullableBlob(index) ?[]const u8`

The `nullableXYZ` functions can safely be called on a `not null` column. The non-nullable versions avoid a call to `sqlite3_column_type` (which is needed in the nullable versions to determine if the value is null or not).

# Transaction:
The `transaction()`, `exclusiveTransaction()`, `commit()` and `rollback()` functions are simply wrappers to `conn.execNoArgs("begin")`, `conn.execNoArgs("begin exclusive")`, `conn.execNoArgs("commit")` and `conn.execNoArgs("rollback")`

```zig
try conn.transaction();
errdefer conn.rollback();

try conn.exec(...);
try conn.exec(...);
try conn.commit();
```

# Blobs
When binding a `[]const u8`, this library has no way to tell whether the value should be treated as an text or blob. It defaults to text. To have the value bound as a blob use `zqlite.blob(value)`:

```zig
conn.insert("insert into records (image) values (?1)", .{zqlite.blob(image)})
```

However, this should only be necessary in specific cases where SQLite blob-specific operations are used on the data. Text and blob are practically the same, except they have a different type.

# Pool
`zqlite.Pool` is a simple thread-safe connection pool. After being created, the `acquire` and `release` functions are used to get a connection from the pool and to release it.

```zig
var pool = try zqlite.Pool.init(allocator, .{
    // The number of connection in the pool. The pool will not grow or
    // shrink beyond this count
    .size = 5,   // default 5

    // The path  of the DB connection
    .path = "/tmp/zqlite.sqlite",  // no default, required

    // The zqlite.OpenFlags to use when opening each connection in the pool
    // Defaults are as shown here:
    .flags = zqlite.OpenFlags.Create | zqlite.OpenFlags.EXResCode

    // Callback function to execute for each connection in the pool when opened
    .on_connection = null,

    // Callback function to execute only for the first connection in the pool
    .on_first_connection = null,
});

const c1 = pool.acquire();
defer c1.release();
c1.execNoArgs(...);
```

## Callbacks
Both the `on_connection` and `on_first_connection` have the same signature. For the first connection to be opened by the pool, if both callbacks are provided then both callbacks will be executed, with `on_first_connection` executing first.

```zig
var pool = zqlite.Pool.init(allocator, .{
    .size = 5,
    .on_first_connection = &initializeDB,
    .on_connection = &initializeConnection,
    // other required & optional fields
});
...

// Our size is 5, but this will only be executed once, for the first
// connection in our pool
fn initializeDB(conn: Conn, _: ?*anyopaque) !void {
    try conn.execNoArgs("create table if not exists testing(id int)");
}

// Our size is 5, so this will be executed 5 times, once for each
// connection. `initializeDB` is guaranteed to be called before this
// function is called.
fn initializeConnection(conn: Conn, _: ?*anyopaque) !void {
    return conn.busyTimeout(1000);
}
```
