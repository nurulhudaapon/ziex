pub fn GET(ctx: zx.RouteContext) !void {
    const uname = ctx.request.cookies.get("username") orelse "";
    if (uname.len == 0) {
        ctx.response.setStatus(.bad_request);
        return ctx.response.setBody("Missing username cookie");
    }

    // Copy username into fixed-size buffer so it's embedded in the struct bytes
    var data = SocketData{};
    const len = @min(uname.len, data.buf.len);
    @memcpy(data.buf[0..len], uname[0..len]);
    data.len = len;

    try ctx.socket.upgrade(data);
}

pub fn SocketOpen(ctx: zx.SocketOpenCtx(SocketData)) !void {
    ctx.socket.configure(.{ .publish_to_self = true });
    ctx.socket.subscribe(CHAT_TOPIC);

    _ = ctx.socket.publish(CHAT_TOPIC, try ctx.fmt(
        "system: {s} joined the chat",
        .{ctx.data.username()},
    ));

    // Send last 5 messages (oldest to newest for correct display with column-reverse)
    const msg_count = messages.items.len;
    const start_idx = if (msg_count > 5) msg_count - 5 else 0;
    for (messages.items[start_idx..]) |msg| {
        try ctx.socket.write(try ctx.fmt(
            "{s}: {s}",
            .{ msg.username, msg.text },
        ));
    }
}

pub fn Socket(ctx: zx.SocketCtx(SocketData)) !void {
    const formatted = try ctx.fmt(
        "{s}: {s}",
        .{ ctx.data.username(), ctx.message },
    );

    _ = ctx.socket.publish(CHAT_TOPIC, formatted);

    messages.append(ctx.allocator, .{
        .text = ctx.allocator.dupe(u8, ctx.message) catch return,
        .username = ctx.allocator.dupe(u8, ctx.data.username()) catch return,
    }) catch return;
}

pub fn SocketClose(ctx: zx.SocketCloseCtx(SocketData)) void {
    const msg = ctx.fmt(
        "system: {s} left the chat",
        .{ctx.data.username()},
    ) catch return;
    _ = ctx.socket.publish(CHAT_TOPIC, msg);
}

var messages = std.ArrayList(Message).empty;

const CHAT_TOPIC = "chat-room";
const Message = struct { text: []const u8, username: []const u8 };

/// Socket data with fixed-size buffer so username bytes are embedded in struct
const SocketData = struct {
    buf: [32]u8 = [_]u8{0} ** 32,
    len: usize = 0,

    pub fn username(self: *const SocketData) []const u8 {
        return self.buf[0..self.len];
    }
};

const std = @import("std");
const zx = @import("zx");
