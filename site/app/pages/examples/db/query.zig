const zx = @import("zx");

pub const Dashboard = struct {
    total_customers: i64,
    total_orders: i64,
    paid_orders: i64,
    total_revenue_cents: i64,
    latest_order_at: []const u8,
};

pub fn init(database: *zx.Db) !void {
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

pub fn seed(database: *zx.Db) !void {
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

pub fn dashboard(database: *zx.Db, allocator: zx.Allocator) !Dashboard {
    const row = (try database.get(allocator,
        \\SELECT
        \\  (SELECT COUNT(*) FROM customers) AS total_customers,
        \\  (SELECT COUNT(*) FROM orders) AS total_orders,
        \\  (SELECT COUNT(*) FROM orders WHERE status = 'paid') AS paid_orders,
        \\  (SELECT COALESCE(SUM(amount_cents), 0) FROM orders WHERE status = 'paid') AS total_revenue_cents,
        \\  (SELECT MAX(created_at) FROM orders) AS latest_order_at
    , .{})).?;

    return .{
        .total_customers = row.int("total_customers"),
        .total_orders = row.int("total_orders"),
        .paid_orders = row.int("paid_orders"),
        .total_revenue_cents = row.int("total_revenue_cents"),
        .latest_order_at = row.text("latest_order_at"),
    };
}
