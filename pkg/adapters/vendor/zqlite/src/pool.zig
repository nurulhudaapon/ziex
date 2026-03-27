const std = @import("std");
const zqlite = @import("zqlite.zig");

const Conn = zqlite.Conn;
const Thread = std.Thread;
const Allocator = std.mem.Allocator;

pub const Pool = struct {
    conns: []Conn,
    available: usize,
    mutex: Thread.Mutex,
    cond: Thread.Condition,
    allocator: Allocator,

    pub const Config = struct {
        size: usize = 5,
        flags: c_int = zqlite.OpenFlags.Create | zqlite.OpenFlags.EXResCode,
        path: [*:0]const u8,
        on_connection: ?*const fn (conn: Conn, context: ?*anyopaque) anyerror!void = null,
        on_first_connection: ?*const fn (conn: Conn, context: ?*anyopaque) anyerror!void = null,
        on_connection_context: ?*anyopaque = null,
        on_first_connection_context: ?*anyopaque = null,
    };

    pub fn init(allocator: Allocator, config: Config) !*Pool {
        const pool = try allocator.create(Pool);
        errdefer allocator.destroy(pool);

        const size = config.size;
        const conns = try allocator.alloc(Conn, size);
        errdefer allocator.free(conns);

        pool.* = .{
            .cond = .{},
            .mutex = .{},
            .conns = conns,
            .available = size,
            .allocator = allocator,
        };

        const path = config.path;
        const flags = config.flags;
        const on_connection = config.on_connection;

        var init_count: usize = 0;
        errdefer {
            for (0..init_count) |i| {
                conns[i].close();
            }
        }

        for (0..size) |i| {
            var conn = try Conn.init(path, flags);
            conn._pool = pool;

            init_count += 1;
            conns[i] = conn;

            if (i == 0) {
                if (config.on_first_connection) |f| {
                    try f(conn, config.on_first_connection_context);
                }
            }
            if (on_connection) |f| {
                try f(conn, config.on_connection_context);
            }
        }

        return pool;
    }

    pub fn deinit(self: *Pool) void {
        const allocator = self.allocator;
        for (self.conns) |conn| {
            conn.close();
        }
        allocator.free(self.conns);
        allocator.destroy(self);
    }

    pub fn acquire(self: *Pool) Conn {
        self.mutex.lock();
        while (true) {
            const conns = self.conns;
            const available = self.available;
            if (available == 0) {
                self.cond.wait(&self.mutex);
                continue;
            }
            const index = available - 1;
            const conn = conns[index];
            self.available = index;
            self.mutex.unlock();
            return conn;
        }
    }

    pub fn release(self: *Pool, conn: Conn) void {
        self.mutex.lock();

        var conns = self.conns;
        const available = self.available;
        conns[available] = conn;
        self.available = available + 1;
        self.mutex.unlock();
        self.cond.signal();
    }
};

const t = std.testing;
test "pool" {
    var context = TestCallbackContext{
        .a = 5,
        .b = 6,
    };

    var pool = try Pool.init(t.allocator, .{
        .size = 2,
        .path = "/tmp/zqlite.test",
        .on_connection = &testPoolEachConnection,
        .on_first_connection = &testPoolFirstConnection,
        .on_connection_context = &context,
        .on_first_connection_context = &context,
    });
    defer pool.deinit();

    const t1 = try std.Thread.spawn(.{}, testPool, .{pool});
    const t2 = try std.Thread.spawn(.{}, testPool, .{pool});
    const t3 = try std.Thread.spawn(.{}, testPool, .{pool});

    t1.join();
    t2.join();
    t3.join();

    const c1 = pool.acquire();
    defer c1.release();

    const row = (try c1.row("select cnt from pool_test", .{})).?;
    try t.expectEqual(@as(i64, 3000), row.int(0));
    row.deinit();

    try c1.execNoArgs("drop table pool_test");
}

const TestCallbackContext = struct {
    a: i32,
    b: i32,
};

fn testPool(p: *Pool) void {
    for (0..1000) |_| {
        const conn = p.acquire();
        conn.execNoArgs("update pool_test set cnt = cnt + 1") catch |err| {
            std.debug.print("update err: {any}\n", .{err});
            unreachable;
        };
        p.release(conn);
    }
}

fn testPoolFirstConnection(conn: Conn, raw_context: ?*anyopaque) !void {
    const context: *const TestCallbackContext = if (raw_context) |rc| @ptrCast(@alignCast(rc)) else {
        return error.TestError;
    };
    try std.testing.expect(context.a == 5);
    try std.testing.expect(context.b == 6);
    try conn.execNoArgs("pragma journal_mode=wal");

    // This is not safe and can result in corruption. This is only set
    // because the tests might be run on really slow hardware and we
    // want to avoid having a busy timeout.
    try conn.execNoArgs("pragma synchronous=off");

    try conn.execNoArgs("drop table if exists pool_test");
    try conn.execNoArgs("create table pool_test (cnt int not null)");
    try conn.execNoArgs("insert into pool_test (cnt) values (0)");
}

fn testPoolEachConnection(conn: Conn, raw_context: ?*anyopaque) !void {
    const context: *const TestCallbackContext = if (raw_context) |rc| @ptrCast(@alignCast(rc)) else {
        return error.TestError;
    };
    try std.testing.expect(context.a == 5);
    try std.testing.expect(context.b == 6);
    return conn.busyTimeout(5000);
}
