const std = @import("std");
const Request = @import("zx").Request;

// --- Type Re-exports --- //

test "Request.Method: is std.http.Method" {
    try std.testing.expect(Request.Method == std.http.Method);
}

test "Request.Version: is std.http.Version" {
    try std.testing.expect(Request.Version == std.http.Version);
}

test "Request.Protocol: is deprecated alias for Version" {
    try std.testing.expect(Request.Protocol == Request.Version);
}

test "Request.Header: is std.http.Header" {
    try std.testing.expect(Request.Header == std.http.Header);
}

// --- Request Instance (without backend) --- //

test "Request: Builder default values" {
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const req = (Request.Builder{ .arena = fba.allocator() }).build();

    try std.testing.expectEqualStrings("", req.url);
    try std.testing.expectEqualStrings("/", req.pathname);
    try std.testing.expectEqualStrings("", req.search);
    try std.testing.expectEqualStrings("", req.referrer);
    try std.testing.expectEqual(Request.Method.GET, req.method);
    try std.testing.expectEqual(Request.Version.@"HTTP/1.1", req.protocol);
}

test "Request: text returns null without backend" {
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const req = (Request.Builder{ .arena = fba.allocator() }).build();
    try std.testing.expect(req.text() == null);
}

test "Request: getParam returns null without backend" {
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const req = (Request.Builder{ .arena = fba.allocator() }).build();
    try std.testing.expect(req.getParam("id") == null);
}

test "Request: cookies field returns Cookies accessor" {
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const req = (Request.Builder{
        .arena = fba.allocator(),
        .cookie_header = "session=abc123",
    }).build();

    try std.testing.expectEqualStrings("abc123", req.cookies.get("session").?);
}

// --- Headers --- //

test "Request.headers: get returns null without backend" {
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const req = (Request.Builder{ .arena = fba.allocator() }).build();
    try std.testing.expect(req.headers.get("Content-Type") == null);
}

test "Request.headers: has returns false without backend" {
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const req = (Request.Builder{ .arena = fba.allocator() }).build();
    try std.testing.expect(!req.headers.has("Content-Type"));
}

// --- URLSearchParams --- //

test "Request.searchParams: get returns null without backend" {
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const req = (Request.Builder{ .arena = fba.allocator() }).build();
    try std.testing.expect(req.searchParams.get("q") == null);
}

test "Request.searchParams: has returns false without backend" {
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const req = (Request.Builder{ .arena = fba.allocator() }).build();
    try std.testing.expect(!req.searchParams.has("q"));
}

// --- Builder --- //

test "Request.Builder: builds with custom values" {
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const req = (Request.Builder{
        .url = "/api/users",
        .method = .POST,
        .pathname = "/api/users",
        .search = "?page=1",
        .referrer = "https://example.com",
        .protocol = .@"HTTP/1.0",
        .cookie_header = "session=xyz",
        .arena = fba.allocator(),
    }).build();

    try std.testing.expectEqualStrings("/api/users", req.url);
    try std.testing.expectEqual(Request.Method.POST, req.method);
    try std.testing.expectEqualStrings("/api/users", req.pathname);
    try std.testing.expectEqualStrings("?page=1", req.search);
    try std.testing.expectEqualStrings("https://example.com", req.referrer);
    try std.testing.expectEqual(Request.Version.@"HTTP/1.0", req.protocol);
    try std.testing.expectEqualStrings("xyz", req.cookies.get("session").?);
}
