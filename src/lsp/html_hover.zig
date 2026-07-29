const std = @import("std");
const lang = @import("lang");
const docs = @import("html_docs.zig");

const Parse = lang.Parse;
const NodeKind = Parse.NodeKind;

/// A located hover target: the documentation Markdown plus the byte span of the
/// token it describes (so the caller can build an LSP range to highlight).
pub const Hover = struct {
    markdown: []const u8,
    start_byte: u32,
    end_byte: u32,
};

/// Parse `source` and, if `offset` falls on an HTML tag name or attribute name,
/// return its hover documentation. Returns null when the cursor is elsewhere
/// (so the caller can fall back to the Zig language server).
///
/// The returned `markdown` is allocated with `arena`.
pub fn hover(arena: std.mem.Allocator, source: []const u8, offset: u32) !?Hover {
    if (offset > source.len) return null;

    var parse = Parse.parse(arena, source, .zx) catch return null;
    defer parse.deinit(arena);

    const root = parse.tree.rootNode();
    const node = root.descendantForByteRange(offset, offset) orelse return null;

    return hoverForNode(arena, &parse, node, source);
}

/// Like `hover`, but returns just the Markdown string (no span). Convenience
/// for callers that don't need the range.
pub fn hoverMarkdown(arena: std.mem.Allocator, source: []const u8, offset: u32) !?[]const u8 {
    const h = try hover(arena, source, offset);
    return if (h) |x| x.markdown else null;
}

fn hoverForNode(arena: std.mem.Allocator, parse: *Parse, node: anytype, source: []const u8) !?Hover {
    const kind = NodeKind.fromNode(node);
    switch (kind) {
        .zx_tag_name => {
            const name = nodeText(node, source);
            const md = try elementMarkdown(arena, name) orelse return null;
            return .{ .markdown = md, .start_byte = node.startByte(), .end_byte = node.endByte() };
        },
        .zx_attribute_name => {
            const attr = nodeText(node, source);
            const tag = enclosingTagName(parse, node, source) orelse "";
            const md = try attributeMarkdown(arena, tag, attr) orelse return null;
            return .{ .markdown = md, .start_byte = node.startByte(), .end_byte = node.endByte() };
        },
        .zx_builtin_name => {
            const raw = nodeText(node, source);
            const md = try builtinAttributeMarkdown(arena, raw) orelse return null;
            return .{ .markdown = md, .start_byte = node.startByte(), .end_byte = node.endByte() };
        },
        else => return null,
    }
}

/// Build Markdown documentation for an element tag name, or null if unknown.
fn elementMarkdown(arena: std.mem.Allocator, name: []const u8) !?[]const u8 {
    const doc = docs.element(name) orelse return null;

    var out: std.Io.Writer.Allocating = .init(arena);
    const w = &out.writer;

    try w.print("**`<{s}>`**\n\n", .{doc.name});

    if (doc.description.len > 0) {
        try w.print("{s}\n", .{doc.description});
    }

    if (doc.href.len > 0) {
        try w.print("\n[MDN Reference]({s})\n", .{doc.href});
    }
    return out.written();
}

/// Build Markdown documentation for an attribute, or null if unknown.
fn attributeMarkdown(arena: std.mem.Allocator, tag: []const u8, attr: []const u8) !?[]const u8 {
    const doc = docs.attribute(tag, attr) orelse return null;

    var out: std.Io.Writer.Allocating = .init(arena);
    const w = &out.writer;

    if (tag.len > 0) {
        try w.print("**`{s}`** attribute of `<{s}>`\n\n", .{ doc.name, tag });
    } else {
        try w.print("**`{s}`** attribute\n\n", .{doc.name});
    }

    if (doc.description.len > 0) {
        try w.print("{s}\n", .{doc.description});
    }
    if (doc.href.len > 0) {
        try w.print("\n[MDN Reference]({s})\n", .{doc.href});
    }
    return out.written();
}

const BuiltinAttrDoc = struct {
    /// Full name including `@` prefix, e.g. `"@rendering"`.
    name: []const u8,
    description: []const u8,
    /// Optional code snippet illustrating usage (Zig/ZX syntax).
    example: []const u8 = "",
};

const builtin_attrs = std.StaticStringMap(BuiltinAttrDoc).initComptime(.{
    .{
        "@rendering",
        BuiltinAttrDoc{
            .name = "@rendering",
            .description =
            \\Controls where a component is rendered.
            \\
            \\**Values**
            \\- `.server` - server-side rendering (default).
            \\- `.client` - client-side Zig, hydrated in the browser.
            \\- `.static` - pre-rendered to static HTML once and cached.
            ,
            .example = "<Counter @rendering={.client} />",
        },
    },
    .{
        "@escaping",
        BuiltinAttrDoc{
            .name = "@escaping",
            .description =
            \\Controls HTML escaping of text content inside the element.
            \\
            \\**Values**
            \\- `.html` - escape HTML special characters (default).
            \\- `.none` - output raw HTML as-is. Use only with trusted content.
            ,
            .example = "<div @escaping={.none}>{raw_html}</div>",
        },
    },
    .{
        "@async",
        BuiltinAttrDoc{
            .name = "@async",
            .description =
            \\Controls asynchronous rendering of a component.
            \\
            \\**Values**
            \\- `.sync` - render synchronously (default).
            \\- `.stream` - render asynchronously; streams the result with an inline script replacement.
            ,
            .example = "<HeavyWidget @async={.stream} />",
        },
    },
    .{
        "@caching",
        BuiltinAttrDoc{
            .name = "@caching",
            .description =
            \\Caches the component output for the given duration.
            \\
            \\Pass a duration string such as `"10s"`, `"5m"`, `"1h"`, `"1d"`,
            \\optionally followed by `:key` to vary the cache by a key.
            \\
            \\**Examples**: `"10s"`, `"5m:user_id"`, `"1h"`, `"1d:slug"`
            ,
            .example = "<Article @caching=\"5m\" />",
        },
    },
    .{
        "@allocator",
        BuiltinAttrDoc{
            .name = "@allocator",
            .description =
            \\Passes an allocator to descendant components that allocate memory.
            \\
            \\Use the shorthand `@{allocator}` as a convenient alternative to
            \\`@allocator={allocator}`.
            ,
            .example = "<section @allocator={arena}><MyComponent /></section>",
        },
    },
    .{
        "@fallback",
        BuiltinAttrDoc{
            .name = "@fallback",
            .description =
            \\Specifies a fallback component to render while an `@async={.stream}`
            \\component is loading.
            ,
            .example = "<HeavyWidget @async={.stream} @fallback={(<Spinner />)} />",
        },
    },
});

/// Build Markdown documentation for a ZX builtin attribute, or null if unknown.
/// `name` must include the `@` prefix (e.g. `"@rendering"`).
fn builtinAttributeMarkdown(arena: std.mem.Allocator, name: []const u8) !?[]const u8 {
    const doc = builtin_attrs.get(name) orelse return null;

    var out: std.Io.Writer.Allocating = .init(arena);
    const w = &out.writer;

    try w.print("**`{s}`** - ZX builtin attribute\n\n", .{doc.name});
    try w.print("{s}\n", .{doc.description});
    if (doc.example.len > 0) {
        try w.print("\n```zx\n{s}\n```\n", .{doc.example});
    }
    return out.written();
}

/// Walk up from an attribute-name node to its enclosing start/self-closing tag
/// and return that tag's name.
fn enclosingTagName(parse: *Parse, node: anytype, source: []const u8) ?[]const u8 {
    _ = parse;
    var current = node.parent();
    while (current) |n| : (current = n.parent()) {
        switch (NodeKind.fromNode(n)) {
            .zx_start_tag, .zx_self_closing_element => {
                const name_node = n.childByFieldName("name") orelse return null;
                return nodeText(name_node, source);
            },
            // Stop once we leave the tag entirely.
            .zx_element, .zx_child => return null,
            else => {},
        }
    }
    return null;
}

fn nodeText(node: anytype, source: []const u8) []const u8 {
    const start = node.startByte();
    const end = node.endByte();
    if (start < end and end <= source.len) return source[start..end];
    return "";
}
