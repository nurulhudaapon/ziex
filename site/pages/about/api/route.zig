// Benchmark WebSocket route - mirrors the Bun benchmark server
// See benches/realtime.mjs for the benchmark client
//
// Optimizations applied:
// 1. Atomic counter for thread-safe client tracking
// 2. Stack buffer for message formatting (avoids allocation in hot path)
// 3. Pub/sub lock contention reduced (see pubsub.zig)

const CLIENTS_TO_WAIT_FOR: u32 = 32;

// Use atomic for thread-safe counter access
var remaining_clients = std.atomic.Value(u32).init(CLIENTS_TO_WAIT_FOR);

pub fn GET(ctx: zx.RouteContext) !void {
    // Get name from query param, or generate one
    const current = remaining_clients.load(.monotonic);
    const name = ctx.request.searchParams.get("name") orelse
        std.fmt.allocPrint(ctx.arena, "Client #{d}", .{CLIENTS_TO_WAIT_FOR - current}) catch "Client";

    try ctx.socket.upgrade(SocketData{
        .name = name,
    });
}

pub fn SocketOpen(ctx: zx.SocketOpenCtx(SocketData)) !void {
    ctx.socket.configure(.{ .publish_to_self = true });
    ctx.socket.subscribe(ROOM_TOPIC);

    // Atomically decrement and get new value
    const prev = remaining_clients.fetchSub(1, .monotonic);
    const current = prev -| 1;
    std.debug.print("{s} connected ({d} remain)\n", .{ ctx.data.name, current });

    // Send immediate welcome to satisfy client's first message wait
    ctx.socket.write("connected") catch {};

    if (current == 0) {
        std.debug.print("All clients connected\n", .{});
        // Reset for next run
        remaining_clients.store(CLIENTS_TO_WAIT_FOR, .monotonic);
        // Send ready message to start the benchmark
        _ = ctx.socket.publish(ROOM_TOPIC, "ready");
    }
}

pub fn Socket(ctx: zx.SocketCtx(SocketData)) !void {
    // Use stack buffer to avoid allocation in hot path
    var buf: [4096]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "{s}: {s}", .{ ctx.data.name, ctx.message }) catch {
        // Fallback to allocated if message is too long
        const allocated = try ctx.fmt("{s}: {s}", .{ ctx.data.name, ctx.message });
        _ = ctx.socket.publish(ROOM_TOPIC, allocated);
        return;
    };
    _ = ctx.socket.publish(ROOM_TOPIC, out);
}

pub fn SocketClose(ctx: zx.SocketCloseCtx(SocketData)) void {
    _ = ctx;
    // Atomically increment
    _ = remaining_clients.fetchAdd(1, .monotonic);
}

const ROOM_TOPIC = "room";
const SocketData = struct { name: []const u8 };

const std = @import("std");
const zx = @import("zx");
