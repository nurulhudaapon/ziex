const zx = @import("zx");

pub const Dashboard = struct {
    total_customers: i64,
    total_orders: i64,
    paid_orders: i64,
    total_revenue_cents: i64,
    latest_order_at: []const u8,
};

pub fn init(database: *zx.db.Connection) !void {
    _ = try database.run(
        \\CREATE TABLE IF NOT EXISTS customers (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  name TEXT NOT NULL,
        \\  email TEXT NOT NULL UNIQUE,
        \\  created_at TEXT DEFAULT CURRENT_TIMESTAMP
        \\)
    , .empty);

    _ = try database.run(
        \\CREATE TABLE IF NOT EXISTS orders (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  customer_email TEXT NOT NULL,
        \\  status TEXT NOT NULL,
        \\  amount_cents INTEGER NOT NULL,
        \\  created_at TEXT DEFAULT CURRENT_TIMESTAMP
        \\)
    , .empty);
}

pub fn seed(database: *zx.db.Connection) !void {
    _ = try database.run(
        \\INSERT OR IGNORE INTO customers (name, email) VALUES
        \\  ('Ava Stone', 'ava@example.com'),
        \\  ('Noah Reed', 'noah@example.com'),
        \\  ('Mina Das', 'mina@example.com')
    , .empty);

    _ = try database.run(
        \\INSERT INTO orders (customer_email, status, amount_cents) VALUES
        \\  ('ava@example.com', 'paid', 2400),
        \\  ('noah@example.com', 'pending', 1800),
        \\  ('mina@example.com', 'paid', 5200)
    , .empty);
}

pub fn dashboard(database: *zx.db.Connection, allocator: zx.Allocator) !Dashboard {
    var statement = try database.query(
        \\SELECT
        \\  (SELECT COUNT(*) FROM customers) AS total_customers,
        \\  (SELECT COUNT(*) FROM orders) AS total_orders,
        \\  (SELECT COUNT(*) FROM orders WHERE status = 'paid') AS paid_orders,
        \\  (SELECT COALESCE(SUM(amount_cents), 0) FROM orders WHERE status = 'paid') AS total_revenue_cents,
        \\  (SELECT MAX(created_at) FROM orders) AS latest_order_at
    );
    defer statement.deinit();

    const row = (try statement.get(allocator, .empty)).?;

    return .{
        .total_customers = asInt(row, "total_customers"),
        .total_orders = asInt(row, "total_orders"),
        .paid_orders = asInt(row, "paid_orders"),
        .total_revenue_cents = asInt(row, "total_revenue_cents"),
        .latest_order_at = asText(row, "latest_order_at"),
    };
}

fn asInt(row: zx.db.Row, name: []const u8) i64 {
    return switch (row.get(name) orelse .null) {
        .integer => |value| value,
        .float => |value| @intFromFloat(value),
        else => 0,
    };
}

fn asText(row: zx.db.Row, name: []const u8) []const u8 {
    return switch (row.get(name) orelse .null) {
        .text => |value| value,
        else => "n/a",
    };
}
