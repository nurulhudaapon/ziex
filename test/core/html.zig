const std = @import("std");
const html = @import("zx").util.html;
const zx = @import("zx");

const testing = std.testing;

fn escape(comptime f: anytype, input: []const u8) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try f(&aw.writer, input);
    return testing.allocator.dupe(u8, aw.written());
}

// ----- escapeAttr -----

test "escapeAttr: plain text unchanged" {
    const r = try escape(html.escapeAttr, "hello world");
    defer testing.allocator.free(r);
    try testing.expectEqualStrings("hello world", r);
}

test "escapeAttr: ampersand" {
    const r = try escape(html.escapeAttr, "a&b");
    defer testing.allocator.free(r);
    try testing.expectEqualStrings("a&amp;b", r);
}

test "escapeAttr: less than" {
    const r = try escape(html.escapeAttr, "<div>");
    defer testing.allocator.free(r);
    try testing.expectEqualStrings("&lt;div&gt;", r);
}

test "escapeAttr: double quote" {
    const r = try escape(html.escapeAttr, "say \"hi\"");
    defer testing.allocator.free(r);
    try testing.expectEqualStrings("say &quot;hi&quot;", r);
}

test "escapeAttr: single quote" {
    const r = try escape(html.escapeAttr, "it's");
    defer testing.allocator.free(r);
    try testing.expectEqualStrings("it&#x27;s", r);
}

test "escapeAttr: all special chars" {
    const r = try escape(html.escapeAttr, "&<>\"'");
    defer testing.allocator.free(r);
    try testing.expectEqualStrings("&amp;&lt;&gt;&quot;&#x27;", r);
}

test "escapeAttr: empty string" {
    const r = try escape(html.escapeAttr, "");
    defer testing.allocator.free(r);
    try testing.expectEqualStrings("", r);
}

// ----- escapeText -----

test "escapeText: plain text unchanged" {
    const r = try escape(html.escapeText, "hello world");
    defer testing.allocator.free(r);
    try testing.expectEqualStrings("hello world", r);
}

test "escapeText: ampersand" {
    const r = try escape(html.escapeText, "a&b&c");
    defer testing.allocator.free(r);
    try testing.expectEqualStrings("a&amp;b&amp;c", r);
}

test "escapeText: angle brackets" {
    const r = try escape(html.escapeText, "<script>alert(1)</script>");
    defer testing.allocator.free(r);
    try testing.expectEqualStrings("&lt;script&gt;alert(1)&lt;/script&gt;", r);
}

test "escapeText: quotes not escaped" {
    const r = try escape(html.escapeText, "say \"hi\" it's");
    defer testing.allocator.free(r);
    try testing.expectEqualStrings("say \"hi\" it's", r);
}

test "escapeText: empty string" {
    const r = try escape(html.escapeText, "");
    defer testing.allocator.free(r);
    try testing.expectEqualStrings("", r);
}

// ----- unescape -----

test "unescape: plain text unchanged" {
    const r = try escape(html.unescape, "hello world");
    defer testing.allocator.free(r);
    try testing.expectEqualStrings("hello world", r);
}

test "unescape: &amp;" {
    const r = try escape(html.unescape, "&amp;");
    defer testing.allocator.free(r);
    try testing.expectEqualStrings("&", r);
}

test "unescape: &lt; and &gt;" {
    const r = try escape(html.unescape, "&lt;div&gt;");
    defer testing.allocator.free(r);
    try testing.expectEqualStrings("<div>", r);
}

test "unescape: &quot;" {
    const r = try escape(html.unescape, "say &quot;hi&quot;");
    defer testing.allocator.free(r);
    try testing.expectEqualStrings("say \"hi\"", r);
}

test "unescape: &#x27;" {
    const r = try escape(html.unescape, "it&#x27;s");
    defer testing.allocator.free(r);
    try testing.expectEqualStrings("it's", r);
}

test "unescape: all entities" {
    const r = try escape(html.unescape, "&amp;&lt;&gt;&quot;&#x27;");
    defer testing.allocator.free(r);
    try testing.expectEqualStrings("&<>\"'", r);
}

test "unescape: unknown entity passthrough" {
    const r = try escape(html.unescape, "&unknown;");
    defer testing.allocator.free(r);
    try testing.expectEqualStrings("&unknown;", r);
}

test "unescape: trailing ampersand" {
    const r = try escape(html.unescape, "hello&");
    defer testing.allocator.free(r);
    try testing.expectEqualStrings("hello&", r);
}

test "unescape: empty string" {
    const r = try escape(html.unescape, "");
    defer testing.allocator.free(r);
    try testing.expectEqualStrings("", r);
}

// ----- Roundtrip -----

test "roundtrip: escapeAttr then unescape" {
    const original = "Tom & Jerry <3 \"quotes\" & 'apostrophes'";
    const escaped = try escape(html.escapeAttr, original);
    defer testing.allocator.free(escaped);
    const unescaped = try escape(html.unescape, escaped);
    defer testing.allocator.free(unescaped);
    try testing.expectEqualStrings(original, unescaped);
}

test "roundtrip: escapeText then unescape" {
    const original = "x < y & y > z";
    const escaped = try escape(html.escapeText, original);
    defer testing.allocator.free(escaped);
    const unescaped = try escape(html.unescape, escaped);
    defer testing.allocator.free(unescaped);
    try testing.expectEqualStrings(original, unescaped);
}

test "prefixBasePath: prefixes root-relative paths" {
    const prefixed = html.prefixPathWithBasePath(testing.allocator, "/docs", "/guide");
    defer if (prefixed.ptr != "/guide".ptr) testing.allocator.free(prefixed);
    try testing.expectEqualStrings("/docs/guide", prefixed);
}

test "prefixBasePath: skips already-prefixed paths" {
    const prefixed = html.prefixPathWithBasePath(testing.allocator, "/docs", "/docs/guide");
    try testing.expectEqualStrings("/docs/guide", prefixed);
}

test "prefixBasePath: skips external and protocol-relative URLs" {
    const external = html.prefixPathWithBasePath(testing.allocator, "/docs", "https://example.com/a");
    const protocol_relative = html.prefixPathWithBasePath(testing.allocator, "/docs", "//cdn.example.com/a");
    try testing.expectEqualStrings("https://example.com/a", external);
    try testing.expectEqualStrings("//cdn.example.com/a", protocol_relative);
}
