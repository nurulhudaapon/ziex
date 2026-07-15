//! Generates `src/lsp/html_docs.zig` - a registry of HTML element and
//! attribute documentation used by the language server for hover tooltips.
//!
//! Data sources (vendored under `vendor/webref`):
//!   - `ed/elements/*.json`  - canonical element list (name, spec href, interface)
//!   - `ed/dfns/html.json`   - element headings ("The div element") and
//!                             `element-attr` definitions (attribute name, the
//!                             elements it applies to, and a spec href)
//!
//! webref does not ship prose descriptions for HTML (unlike CSS), so a small
//! curated table of one-line summaries is hardcoded, TODO: later we can use the JSON file from VSCode HTML Language Service for better docs
//!
//! Run `zig build htmldocsgen` to regenerate.

const std = @import("std");

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

const ElementDoc = struct {
    name: []const u8,
    href: []const u8 = "",
    interface: []const u8 = "",
    title: []const u8 = "",
    description: []const u8 = "",
};

const AttrDoc = struct {
    /// Attribute name.
    name: []const u8,
    /// Element this applies to ("" / "global" for global attributes).
    element: []const u8,
    href: []const u8 = "",
    description: []const u8 = "",
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    const source = try generate(io, allocator);
    defer allocator.free(source);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = "src/lsp/html_docs.zig",
        .data = source,
    });
    std.debug.print("Generated src/lsp/html_docs.zig\n", .{});
}

pub fn generate(io: std.Io, allocator: std.mem.Allocator) ![]const u8 {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    // Step 1: collect elements from ed/elements/*.json.
    var elements = std.StringHashMap(ElementDoc).init(a);

    var el_dir = try std.Io.Dir.cwd().openDir(io, "vendor/webref/ed/elements", .{ .iterate = true });
    defer el_dir.close(io);
    var el_it = el_dir.iterate();
    while (try el_it.next(io)) |entry| {
        if (!std.mem.endsWith(u8, entry.name, ".json")) continue;
        const content = try el_dir.readFileAlloc(io, entry.name, a, .unlimited);
        const parsed = std.json.parseFromSlice(std.json.Value, a, content, .{}) catch continue;
        const els = (parsed.value.object.get("elements") orelse continue).array;
        for (els.items) |el| {
            const name = (el.object.get("name") orelse continue).string;
            // Skip duplicates (some specs redefine elements); first wins.
            if (elements.contains(name)) continue;
            try elements.put(name, .{
                .name = name,
                .href = if (el.object.get("href")) |h| h.string else "",
                .interface = if (el.object.get("interface")) |i| i.string else "",
            });
        }
    }

    // Step 2: read ed/dfns/html.json for element headings and attributes.
    var attrs: std.ArrayListUnmanaged(AttrDoc) = .empty;

    const dfns_content = try std.Io.Dir.cwd().readFileAlloc(io, "vendor/webref/ed/dfns/html.json", a, .unlimited);
    const dfns_parsed = try std.json.parseFromSlice(std.json.Value, a, dfns_content, .{});
    const dfns = (dfns_parsed.value.object.get("dfns") orelse return error.BadWebref).array;

    for (dfns.items) |dfn| {
        const dtype = (dfn.object.get("type") orelse continue).string;
        const linking = (dfn.object.get("linkingText") orelse continue).array;
        if (linking.items.len == 0) continue;
        const text = linking.items[0].string;
        const href = if (dfn.object.get("href")) |h| h.string else "";

        if (eql(dtype, "element")) {
            if (elements.getPtr(text)) |el| {
                if (dfn.object.get("heading")) |heading| {
                    if (heading.object.get("title")) |t| el.title = t.string;
                }
                if (el.href.len == 0) el.href = href;
            }
        } else if (eql(dtype, "element-attr")) {
            const for_arr = if (dfn.object.get("for")) |f| f.array.items else &.{};
            if (for_arr.len == 0) {
                try attrs.append(a, .{ .name = text, .element = "global", .href = href });
            } else {
                for (for_arr) |scope| {
                    try attrs.append(a, .{ .name = text, .element = scope.string, .href = href });
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // Step 3: layer curated descriptions on top of the webref-derived data.
    // -------------------------------------------------------------------------
    for (curated_elements) |c| {
        if (elements.getPtr(c.name)) |el| {
            el.description = c.description;
        } else {
            try elements.put(c.name, .{ .name = c.name, .description = c.description });
        }
    }

    // -------------------------------------------------------------------------
    // Step 4: emit the registry.
    // -------------------------------------------------------------------------
    var out: std.Io.Writer.Allocating = .init(a);
    const w = &out.writer;

    try w.writeAll(
        \\//! Generated by tools/codegen/html_docs.zig - do not edit manually.
        \\//! Run `zig build htmldocsgen` to regenerate.
        \\//!
        \\//! HTML element/attribute documentation for language-server hover.
        \\//! Lookups are ASCII case-insensitive.
        \\
        \\const std = @import("std");
        \\
        \\pub const ElementDoc = struct {
        \\    /// Tag name, e.g. "div".
        \\    name: []const u8,
        \\    /// One-line summary (may be empty).
        \\    description: []const u8 = "",
        \\    /// DOM interface name, e.g. "HTMLDivElement" (may be empty).
        \\    interface: []const u8 = "",
        \\    /// Spec heading title, e.g. "The div element" (may be empty).
        \\    title: []const u8 = "",
        \\    /// Link to the canonical specification (may be empty).
        \\    href: []const u8 = "",
        \\};
        \\
        \\pub const AttributeDoc = struct {
        \\    /// Attribute name, e.g. "href".
        \\    name: []const u8,
        \\    /// One-line summary (may be empty).
        \\    description: []const u8 = "",
        \\    /// Link to the canonical specification (may be empty).
        \\    href: []const u8 = "",
        \\};
        \\
        \\const Map = std.StaticStringMapWithEql(
        \\    ElementDoc,
        \\    std.static_string_map.eqlAsciiIgnoreCase,
        \\);
        \\
        \\const AttrMap = std.StaticStringMapWithEql(
        \\    AttributeDoc,
        \\    std.static_string_map.eqlAsciiIgnoreCase,
        \\);
        \\
        \\
    );

    // Element registry.
    try w.writeAll("const elements = Map.initComptime(.{\n");
    // Deterministic order: sort element keys.
    var el_keys: std.ArrayListUnmanaged([]const u8) = .empty;
    {
        var kit = elements.keyIterator();
        while (kit.next()) |k| try el_keys.append(a, k.*);
    }
    std.mem.sort([]const u8, el_keys.items, {}, lessThan);
    for (el_keys.items) |k| {
        const el = elements.get(k).?;
        try w.print("    .{{ \"{f}\", ElementDoc{{ .name = \"{f}\", .description = \"{f}\", .interface = \"{f}\", .title = \"{f}\", .href = \"{f}\" }} }},\n", .{
            zigEscape(k),            zigEscape(el.name),  zigEscape(el.description),
            zigEscape(el.interface), zigEscape(el.title), zigEscape(el.href),
        });
    }
    try w.writeAll("});\n\n");

    // Per-attribute registries: one StaticStringMap per element scope plus a
    // global map. Keyed lookups go: try element-specific, then global.
    //
    // Build attribute key as "<element>\x00<attr>" in a single flat map for
    // element-scoped attributes, plus a separate global map.
    try w.writeAll("const global_attributes = AttrMap.initComptime(.{\n");
    var seen_global = std.StringHashMap(void).init(a);
    var curated_global = std.StringHashMap([]const u8).init(a);
    for (curated_attributes) |c| {
        if (eql(c.element, "global")) try curated_global.put(c.name, c.description);
    }
    {
        var global_keys: std.ArrayListUnmanaged([]const u8) = .empty;
        var seen_tmp = std.StringHashMap(void).init(a);
        for (attrs.items) |at| {
            if (!isGlobalScope(at.element)) continue;
            if (seen_tmp.contains(at.name)) continue;
            try seen_tmp.put(at.name, {});
            try global_keys.append(a, at.name);
        }
        // Include curated globals that webref may not list.
        for (curated_attributes) |c| {
            if (!eql(c.element, "global")) continue;
            if (seen_tmp.contains(c.name)) continue;
            try seen_tmp.put(c.name, {});
            try global_keys.append(a, c.name);
        }
        std.mem.sort([]const u8, global_keys.items, {}, lessThan);
        for (global_keys.items) |name| {
            try seen_global.put(name, {});
            const href = attrHref(attrs.items, "", name);
            const desc = curated_global.get(name) orelse "";
            try w.print("    .{{ \"{f}\", AttributeDoc{{ .name = \"{f}\", .description = \"{f}\", .href = \"{f}\" }} }},\n", .{
                zigEscape(name), zigEscape(name), zigEscape(desc), zigEscape(href),
            });
        }
    }
    try w.writeAll("});\n\n");

    // Element-scoped attributes: flat map keyed by "element\tattr".
    try w.writeAll("// Keyed by \"<element>\\t<attr>\" (lower-case element).\n");
    try w.writeAll("const element_attributes = AttrMap.initComptime(.{\n");
    {
        var curated_scoped = std.StringHashMap([]const u8).init(a);
        for (curated_attributes) |c| {
            if (eql(c.element, "global")) continue;
            const key = try std.fmt.allocPrint(a, "{s}\t{s}", .{ c.element, c.name });
            try curated_scoped.put(key, c.description);
        }
        var keys: std.ArrayListUnmanaged([]const u8) = .empty;
        var seen = std.StringHashMap(void).init(a);
        for (attrs.items) |at| {
            if (isGlobalScope(at.element)) continue;
            const key = try std.fmt.allocPrint(a, "{s}\t{s}", .{ at.element, at.name });
            if (seen.contains(key)) continue;
            try seen.put(key, {});
            try keys.append(a, key);
        }
        var cit = curated_scoped.keyIterator();
        while (cit.next()) |k| {
            if (seen.contains(k.*)) continue;
            try seen.put(k.*, {});
            try keys.append(a, k.*);
        }
        std.mem.sort([]const u8, keys.items, {}, lessThan);
        for (keys.items) |key| {
            const tab = std.mem.indexOfScalar(u8, key, '\t').?;
            const element = key[0..tab];
            const attr = key[tab + 1 ..];
            const href = attrHref(attrs.items, element, attr);
            const desc = curated_scoped.get(key) orelse "";
            try w.print("    .{{ \"{f}\\t{f}\", AttributeDoc{{ .name = \"{f}\", .description = \"{f}\", .href = \"{f}\" }} }},\n", .{
                zigEscape(element), zigEscape(attr), zigEscape(attr), zigEscape(desc), zigEscape(href),
            });
        }
    }
    try w.writeAll("});\n\n");

    try w.writeAll(
        \\/// Look up documentation for an HTML element by tag name.
        \\pub fn element(name: []const u8) ?ElementDoc {
        \\    return elements.get(name);
        \\}
        \\
        \\/// Look up documentation for an attribute. Tries the element-specific
        \\/// definition first, then falls back to global attributes. Element and
        \\/// attribute name matching is ASCII case-insensitive (the underlying
        \\/// maps use eqlAsciiIgnoreCase), so the "<element>\t<attr>" key only
        \\/// needs the raw bytes joined.
        \\pub fn attribute(tag: []const u8, attr: []const u8) ?AttributeDoc {
        \\    var buf: [128]u8 = undefined;
        \\    if (tag.len + 1 + attr.len <= buf.len) {
        \\        @memcpy(buf[0..tag.len], tag);
        \\        buf[tag.len] = '\t';
        \\        @memcpy(buf[tag.len + 1 ..][0..attr.len], attr);
        \\        const key = buf[0 .. tag.len + 1 + attr.len];
        \\        if (element_attributes.get(key)) |d| return d;
        \\    }
        \\    return global_attributes.get(attr);
        \\}
        \\
    );

    return allocator.dupe(u8, out.written());
}

fn isGlobalScope(scope: []const u8) bool {
    return eql(scope, "global") or eql(scope, "html-global") or
        eql(scope, "htmlsvg-global") or eql(scope, "html-element");
}

fn attrHref(items: []const AttrDoc, element: []const u8, name: []const u8) []const u8 {
    for (items) |at| {
        if (!eql(at.name, name)) continue;
        if (element.len == 0) {
            if (isGlobalScope(at.element)) return at.href;
        } else if (eql(at.element, element)) {
            return at.href;
        }
    }
    return "";
}

fn lessThan(_: void, l: []const u8, r: []const u8) bool {
    return std.mem.lessThan(u8, l, r);
}

/// Escapes a string for embedding inside a Zig `"..."` literal.
const ZigEscape = struct {
    s: []const u8,
    pub fn format(self: ZigEscape, w: *std.Io.Writer) !void {
        for (self.s) |c| switch (c) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            else => try w.writeByte(c),
        };
    }
};

fn zigEscape(s: []const u8) ZigEscape {
    return .{ .s = s };
}

const Curated = struct { name: []const u8, description: []const u8 };

const curated_elements = [_]Curated{
    .{ .name = "a", .description = "Hyperlink to other pages, files, locations, or anything a URL can address." },
    .{ .name = "abbr", .description = "An abbreviation or acronym; use the title attribute for the full term." },
    .{ .name = "article", .description = "A self-contained composition, intended to be independently distributable." },
    .{ .name = "aside", .description = "Content tangentially related to the surrounding content (e.g. a sidebar)." },
    .{ .name = "audio", .description = "Embeds sound content; provide <source> children or a src attribute." },
    .{ .name = "b", .description = "Stylistically offset text without conveying extra importance (bold)." },
    .{ .name = "button", .description = "A clickable button. Use type to control submit/reset/button behavior." },
    .{ .name = "canvas", .description = "A bitmap canvas for scripted graphics rendering." },
    .{ .name = "code", .description = "A fragment of computer code." },
    .{ .name = "details", .description = "A disclosure widget that can be toggled open and closed." },
    .{ .name = "div", .description = "A generic flow-content container with no special meaning." },
    .{ .name = "em", .description = "Stress emphasis (typically rendered in italics)." },
    .{ .name = "footer", .description = "A footer for its nearest sectioning content or the page." },
    .{ .name = "form", .description = "A section containing interactive controls for submitting information." },
    .{ .name = "h1", .description = "Section heading, level 1 (highest)." },
    .{ .name = "h2", .description = "Section heading, level 2." },
    .{ .name = "h3", .description = "Section heading, level 3." },
    .{ .name = "h4", .description = "Section heading, level 4." },
    .{ .name = "h5", .description = "Section heading, level 5." },
    .{ .name = "h6", .description = "Section heading, level 6 (lowest)." },
    .{ .name = "header", .description = "Introductory content or navigational aids for its section/page." },
    .{ .name = "hr", .description = "A thematic break between paragraph-level content (void element)." },
    .{ .name = "i", .description = "Text in an alternate voice or mood (typically italic)." },
    .{ .name = "iframe", .description = "Embeds another HTML page into the current one." },
    .{ .name = "img", .description = "Embeds an image. Requires src; always provide alt text (void element)." },
    .{ .name = "input", .description = "A typed form control. The type attribute selects the control kind (void)." },
    .{ .name = "label", .description = "A caption for a form control; associate via for or by nesting." },
    .{ .name = "li", .description = "A list item within <ol>, <ul>, or <menu>." },
    .{ .name = "link", .description = "Relationship to an external resource, e.g. a stylesheet (void element)." },
    .{ .name = "main", .description = "The dominant content of the document's <body>." },
    .{ .name = "meta", .description = "Document-level metadata that other elements can't express (void element)." },
    .{ .name = "nav", .description = "A section of navigation links." },
    .{ .name = "ol", .description = "An ordered (numbered) list of items." },
    .{ .name = "option", .description = "An option within a <select>, <optgroup>, or <datalist>." },
    .{ .name = "p", .description = "A paragraph of text." },
    .{ .name = "pre", .description = "Preformatted text; whitespace and line breaks are preserved." },
    .{ .name = "script", .description = "Embeds or references executable script." },
    .{ .name = "section", .description = "A generic standalone section of a document." },
    .{ .name = "select", .description = "A control for selecting among a set of <option> elements." },
    .{ .name = "span", .description = "A generic inline container with no special meaning." },
    .{ .name = "strong", .description = "Strong importance, seriousness, or urgency (typically bold)." },
    .{ .name = "style", .description = "Embeds CSS style information in the document." },
    .{ .name = "svg", .description = "Embeds Scalable Vector Graphics content." },
    .{ .name = "table", .description = "Tabular data arranged in rows and columns." },
    .{ .name = "tbody", .description = "Groups the body rows of a <table>." },
    .{ .name = "td", .description = "A data cell in a table row." },
    .{ .name = "template", .description = "Holds inert HTML fragments to be cloned by script." },
    .{ .name = "textarea", .description = "A multiline plain-text editing control." },
    .{ .name = "th", .description = "A header cell in a table." },
    .{ .name = "thead", .description = "Groups the header rows of a <table>." },
    .{ .name = "title", .description = "The document's title, shown in the browser tab/title bar." },
    .{ .name = "tr", .description = "A row of cells in a table." },
    .{ .name = "ul", .description = "An unordered (bulleted) list of items." },
    .{ .name = "video", .description = "Embeds video content; provide <source> children or a src attribute." },
};

const curated_attributes = [_]struct {
    name: []const u8,
    element: []const u8,
    description: []const u8,
}{
    // Global attributes
    .{ .name = "id", .element = "global", .description = "A unique identifier for the element, used by CSS, scripts, and fragment links." },
    .{ .name = "class", .element = "global", .description = "A space-separated list of the element's CSS classes." },
    .{ .name = "style", .element = "global", .description = "Inline CSS declarations for this element." },
    .{ .name = "title", .element = "global", .description = "Advisory information, typically shown as a tooltip." },
    .{ .name = "hidden", .element = "global", .description = "Hides the element from rendering when present." },
    .{ .name = "lang", .element = "global", .description = "The primary language of the element's contents (BCP 47)." },
    .{ .name = "dir", .element = "global", .description = "Text directionality: ltr, rtl, or auto." },
    .{ .name = "tabindex", .element = "global", .description = "Controls whether and in what order the element is focusable." },
    .{ .name = "role", .element = "global", .description = "ARIA role describing the element's purpose to assistive technology." },
    .{ .name = "contenteditable", .element = "global", .description = "Whether the element's content is editable by the user." },
    .{ .name = "draggable", .element = "global", .description = "Whether the element can be dragged (true/false)." },
    // Common element-specific attributes
    .{ .name = "href", .element = "a", .description = "The URL the hyperlink points to." },
    .{ .name = "target", .element = "a", .description = "Where to open the link, e.g. _blank, _self." },
    .{ .name = "rel", .element = "a", .description = "Relationship of the linked resource to the current document." },
    .{ .name = "src", .element = "img", .description = "The image URL to display (required)." },
    .{ .name = "alt", .element = "img", .description = "Alternative text describing the image for accessibility." },
    .{ .name = "src", .element = "script", .description = "URL of an external script to load." },
    .{ .name = "type", .element = "input", .description = "The kind of input control (text, checkbox, email, ...)." },
    .{ .name = "name", .element = "input", .description = "The control's name, submitted with the form data." },
    .{ .name = "value", .element = "input", .description = "The control's current value." },
    .{ .name = "placeholder", .element = "input", .description = "A short hint shown when the control is empty." },
    .{ .name = "type", .element = "button", .description = "Button behavior: submit, reset, or button." },
    .{ .name = "for", .element = "label", .description = "The id of the form control this label is bound to." },
    .{ .name = "rel", .element = "link", .description = "Relationship of the linked resource, e.g. stylesheet." },
    .{ .name = "href", .element = "link", .description = "URL of the linked resource." },
};
