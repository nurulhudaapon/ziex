const std = @import("std");
const Response = @import("zx").Response;

// --- Type Re-exports --- //

test "Response.HttpStatus: is std.http.Status" {
    try std.testing.expect(Response.HttpStatus == std.http.Status);
}

test "Response.ContentType: is common.ContentType" {
    // Verify it exists and has expected variants
    try std.testing.expectEqualStrings("text/html", Response.ContentType.@"text/html".toString());
}

test "Response.CookieOptions: is common.CookieOptions" {
    const opts = Response.CookieOptions{};
    try std.testing.expectEqualStrings("", opts.path);
}

test "Response.Headers: exists and has expected methods" {
    const headers = Response.Headers{};
    // Response.Headers has get, set, add methods
    try std.testing.expect(headers.get("X-Test") == null);
}

// --- Response Instance (Web Standard Properties) --- //

test "Response: default field values" {
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const res = Response{ .arena = fba.allocator() };

    try std.testing.expectEqualStrings("", res.body);
    try std.testing.expect(!res.bodyUsed);
    try std.testing.expect(res.ok);
    try std.testing.expect(!res.redirected);
    try std.testing.expectEqual(@as(u16, 200), res.status);
    try std.testing.expectEqualStrings("OK", res.statusText);
    try std.testing.expectEqual(Response.ResponseType.default, res.type);
    try std.testing.expectEqualStrings("", res.url);
}

test "Response: ok is true for 2xx status" {
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const res200 = (Response.Builder{ .status = 200, .arena = fba.allocator() }).build();
    const res201 = (Response.Builder{ .status = 201, .arena = fba.allocator() }).build();
    const res299 = (Response.Builder{ .status = 299, .arena = fba.allocator() }).build();

    try std.testing.expect(res200.ok);
    try std.testing.expect(res201.ok);
    try std.testing.expect(res299.ok);
}

test "Response: ok is false for non-2xx status" {
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const res199 = (Response.Builder{ .status = 199, .arena = fba.allocator() }).build();
    const res300 = (Response.Builder{ .status = 300, .arena = fba.allocator() }).build();
    const res404 = (Response.Builder{ .status = 404, .arena = fba.allocator() }).build();
    const res500 = (Response.Builder{ .status = 500, .arena = fba.allocator() }).build();

    try std.testing.expect(!res199.ok);
    try std.testing.expect(!res300.ok);
    try std.testing.expect(!res404.ok);
    try std.testing.expect(!res500.ok);
}

test "Response: statusText is set from status code" {
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const res200 = (Response.Builder{ .status = 200, .arena = fba.allocator() }).build();
    const res404 = (Response.Builder{ .status = 404, .arena = fba.allocator() }).build();
    const res500 = (Response.Builder{ .status = 500, .arena = fba.allocator() }).build();

    try std.testing.expectEqualStrings("OK", res200.statusText);
    try std.testing.expectEqualStrings("Not Found", res404.statusText);
    try std.testing.expectEqualStrings("Internal Server Error", res500.statusText);
}

// --- ResponseType --- //

test "Response.ResponseType: all values" {
    const types = [_]Response.ResponseType{
        .basic, .cors, .default, .@"error", .@"opaque", .opaqueredirect,
    };
    try std.testing.expectEqual(6, types.len);
}

// --- Builder --- //

test "Response.Builder: builds with custom values" {
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const res = (Response.Builder{
        .status = 201,
        .url = "https://example.com/api",
        .response_type = .cors,
        .arena = fba.allocator(),
    }).build();

    try std.testing.expectEqual(@as(u16, 201), res.status);
    try std.testing.expect(res.ok);
    try std.testing.expectEqualStrings("Created", res.statusText);
    try std.testing.expectEqualStrings("https://example.com/api", res.url);
    try std.testing.expectEqual(Response.ResponseType.cors, res.type);
}

// --- Methods (without backend) --- //

test "Response.setStatus: no-op without backend" {
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const res = (Response.Builder{ .arena = fba.allocator() }).build();

    // Should not crash, but local fields remain unchanged
    res.setStatus(.not_found);
    try std.testing.expectEqual(@as(u16, 200), res.status);
}

test "Response.setStatusCode: no-op without backend" {
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const res = (Response.Builder{ .arena = fba.allocator() }).build();

    res.setStatusCode(503);
    try std.testing.expectEqual(@as(u16, 200), res.status);
}

test "Response.setBody: no-op without backend" {
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const res = (Response.Builder{ .arena = fba.allocator() }).build();

    res.setBody("Hello");
    try std.testing.expectEqualStrings("", res.body);
}

test "Response.redirect: no-op without backend" {
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const res = (Response.Builder{ .arena = fba.allocator() }).build();

    res.redirect("/new", null);
    res.redirect("/permanent", 301);
    try std.testing.expectEqual(@as(u16, 200), res.status);
    try std.testing.expect(!res.redirected);
}

// --- Headers --- //

test "Response.headers: get returns null without backend" {
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const res = Response{ .arena = fba.allocator() };
    try std.testing.expect(res.headers.get("Content-Type") == null);
}

test "Response.headers: set and add are no-op without backend" {
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const res = Response{ .arena = fba.allocator() };
    // These should not crash (no-op without backend)
    res.headers.set("X-Test", "value");
    res.headers.add("X-Test", "value2");
}
