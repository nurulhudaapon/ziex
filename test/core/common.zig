const std = @import("std");
// Access common types through Request/Response which re-export them
const Request = @import("zx").Request;
const Response = @import("zx").Response;

// --- Cookies (accessed via Request) --- //

test "Cookies: get returns value" {
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const req = (Request.Builder{
        .arena = fba.allocator(),
        .cookie_header = "session=abc123; user=john",
    }).build();

    try std.testing.expectEqualStrings("abc123", req.cookies.get("session").?);
    try std.testing.expectEqualStrings("john", req.cookies.get("user").?);
}

test "Cookies: get returns null for missing cookie" {
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const req = (Request.Builder{
        .arena = fba.allocator(),
        .cookie_header = "session=abc123",
    }).build();

    try std.testing.expectEqual(null, req.cookies.get("missing"));
}

test "Cookies: handles empty header" {
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const req = (Request.Builder{
        .arena = fba.allocator(),
        .cookie_header = "",
    }).build();

    try std.testing.expectEqual(null, req.cookies.get("session"));
}

test "Cookies: handles spaces after semicolon" {
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const req = (Request.Builder{
        .arena = fba.allocator(),
        .cookie_header = "a=1; b=2;  c=3",
    }).build();

    try std.testing.expectEqualStrings("1", req.cookies.get("a").?);
    try std.testing.expectEqualStrings("2", req.cookies.get("b").?);
    try std.testing.expectEqualStrings("3", req.cookies.get("c").?);
}

// --- CookieOptions (accessed via Response) --- //

test "CookieOptions: defaults" {
    const opts = Response.CookieOptions{};
    try std.testing.expectEqualStrings("", opts.path);
    try std.testing.expectEqualStrings("", opts.domain);
    try std.testing.expectEqual(null, opts.max_age);
    try std.testing.expect(!opts.secure);
    try std.testing.expect(!opts.http_only);
    try std.testing.expect(!opts.partitioned);
    try std.testing.expectEqual(null, opts.same_site);
}

test "CookieOptions: with all values" {
    const opts = Response.CookieOptions{
        .path = "/api",
        .domain = "example.com",
        .max_age = 3600,
        .secure = true,
        .http_only = true,
        .partitioned = true,
        .same_site = .strict,
    };
    try std.testing.expectEqualStrings("/api", opts.path);
    try std.testing.expectEqualStrings("example.com", opts.domain);
    try std.testing.expectEqual(@as(?i32, 3600), opts.max_age);
    try std.testing.expect(opts.secure);
    try std.testing.expect(opts.http_only);
    try std.testing.expect(opts.partitioned);
    try std.testing.expectEqual(Response.CookieOptions.SameSite.strict, opts.same_site.?);
}

test "CookieOptions.SameSite: all values" {
    const values = [_]Response.CookieOptions.SameSite{ .lax, .strict, .none };
    try std.testing.expectEqual(3, values.len);
}

// --- ContentType (accessed via Response) --- //

test "ContentType: toString returns MIME type" {
    try std.testing.expectEqualStrings("text/html", Response.ContentType.@"text/html".toString());
    try std.testing.expectEqualStrings("application/json", Response.ContentType.@"application/json".toString());
    try std.testing.expectEqualStrings("application/wasm", Response.ContentType.@"application/wasm".toString());
    try std.testing.expectEqualStrings("image/png", Response.ContentType.@"image/png".toString());
}

// --- MultiFormEntry (accessed via Request) --- //

test "MultiFormEntry: fields" {
    const entry = Request.MultiFormEntry{
        .key = "file",
        .value = "binary data",
        .filename = "photo.jpg",
    };
    try std.testing.expectEqualStrings("file", entry.key);
    try std.testing.expectEqualStrings("binary data", entry.value);
    try std.testing.expectEqualStrings("photo.jpg", entry.filename.?);
}

test "MultiFormEntry: filename can be null" {
    const entry = Request.MultiFormEntry{
        .key = "name",
        .value = "John",
        .filename = null,
    };
    try std.testing.expectEqual(null, entry.filename);
}
