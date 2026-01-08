const std = @import("std");
const Headers = @import("zx").Headers;

// --- Type Re-exports --- //

test "Headers.Header: is std.http.Header" {
    try std.testing.expect(Headers.Header == std.http.Header);
}

test "Headers.HeaderIterator: is std.http.HeaderIterator" {
    try std.testing.expect(Headers.HeaderIterator == std.http.HeaderIterator);
}

// --- HeaderIterator Usage --- //

test "Headers.HeaderIterator: parses raw HTTP headers" {
    const raw = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nX-Custom: value\r\n\r\n";
    var iter = Headers.HeaderIterator.init(raw);

    const h1 = iter.next().?;
    try std.testing.expectEqualStrings("Content-Type", h1.name);
    try std.testing.expectEqualStrings("text/html", h1.value);

    const h2 = iter.next().?;
    try std.testing.expectEqualStrings("X-Custom", h2.name);
    try std.testing.expectEqualStrings("value", h2.value);

    try std.testing.expect(iter.next() == null);
}

// --- Headers Instance (without backend) --- //

test "Headers: default is read-only" {
    const headers = Headers{};
    try std.testing.expect(headers.isReadOnly());
}

test "Headers: can be set to writable" {
    const headers = Headers{ .read_only = false };
    try std.testing.expect(!headers.isReadOnly());
}

test "Headers: get returns null without backend" {
    const headers = Headers{};
    try std.testing.expect(headers.get("Content-Type") == null);
}

test "Headers: has returns false without backend" {
    const headers = Headers{};
    try std.testing.expect(!headers.has("Content-Type"));
}

test "Headers: entries returns null without backend" {
    const headers = Headers{};
    try std.testing.expect(headers.entries() == null);
}

test "Headers: write methods are no-op without backend" {
    var headers = Headers{ .read_only = false };
    // These should not crash
    headers.append("X-Test", "value");
    headers.set("X-Test", "value");
    headers.delete("X-Test");
}

test "Headers: write methods are no-op when read-only" {
    var headers = Headers{}; // read_only = true by default
    // These should not crash and should be no-ops
    headers.append("X-Test", "value");
    headers.set("X-Test", "value");
}

// --- Builder --- //

test "Headers.Builder: builds with defaults" {
    const headers = (Headers.Builder{}).build();
    try std.testing.expect(headers.read_only);
    try std.testing.expect(headers.backend_ctx == null);
    try std.testing.expect(headers.vtable == null);
}

test "Headers.Builder: builds with custom values" {
    const headers = (Headers.Builder{
        .read_only = false,
    }).build();
    try std.testing.expect(!headers.read_only);
}
