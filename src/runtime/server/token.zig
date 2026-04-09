const std = @import("std");
const zx_options = @import("zx_options");

const server_action_salt = "zx_options.server_action_salt";

const signature_len = 8;
const token_len = 8 + (signature_len * 2);

fn actionMask() u32 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(server_action_salt, &digest, .{});
    return std.mem.readInt(u32, digest[0..4], .big);
}

fn signature(masked_action_id: u32) [signature_len]u8 {
    var masked_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &masked_buf, masked_action_id, .big);

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(server_action_salt);
    hasher.update(&masked_buf);

    var digest: [32]u8 = undefined;
    hasher.final(&digest);

    var out: [signature_len]u8 = undefined;
    @memcpy(&out, digest[0..signature_len]);
    return out;
}

pub fn writeToken(writer: *std.Io.Writer, action_id: u32) !void {
    const masked_action_id = action_id ^ actionMask();
    const sig = signature(masked_action_id);

    try writer.print("{x:0>8}", .{masked_action_id});
    for (sig) |byte| {
        try writer.print("{x:0>2}", .{byte});
    }
}

fn parseHexDigit(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

fn parseHexInt(comptime T: type, raw: []const u8) ?T {
    var value: T = 0;
    for (raw) |c| {
        const nibble = parseHexDigit(c) orelse return null;
        value = (value << 4) | @as(T, nibble);
    }
    return value;
}

pub fn decodeToken(raw: []const u8) ?u32 {
    if (raw.len == 0) return null;

    // Backward-compatible fallback for old plain numeric action ids.
    if (raw.len != token_len) {
        const action_id = std.fmt.parseInt(u32, raw, 10) catch return null;
        return if (action_id == 0) null else action_id;
    }

    const masked_action_id = parseHexInt(u32, raw[0..8]) orelse return null;
    const expected_sig = signature(masked_action_id);

    var actual_sig: [signature_len]u8 = undefined;
    for (0..signature_len) |i| {
        const start = 8 + (i * 2);
        actual_sig[i] = parseHexInt(u8, raw[start .. start + 2]) orelse return null;
    }

    if (!std.crypto.utils.timingSafeEql([signature_len]u8, actual_sig, expected_sig)) return null;
    const action_id = masked_action_id ^ actionMask();
    return if (action_id == 0) null else action_id;
}
