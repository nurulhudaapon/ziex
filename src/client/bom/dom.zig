//! DOM bindings for client-side JavaScript interop.
//! Provides Zig interfaces to browser Document and Element APIs.
//! On server builds, these types exist but their methods are no-ops.

const std = @import("std");
const builtin = @import("builtin");
const bom = @import("../bom.zig");
const Console = bom.Console;

/// Whether we're running in a browser environment (WASM)
const is_wasm = bom.is_wasm;

/// JS Object type - real in WASM, void stub on server
const JsObject = if (is_wasm) @import("js").Object else void;

pub const Document = @This();

pub const HTMLElement = struct {
    ref: JsObject,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, ref: JsObject) HTMLElement {
        return .{
            .ref = ref,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: HTMLElement) void {
        if (!is_wasm) return;
        self.ref.deinit();
    }

    pub fn setInnerHTML(self: HTMLElement, html: []const u8) !void {
        if (!is_wasm) return;
        try self.ref.set("innerHTML", @import("js").string(html));
    }

    pub fn appendChild(self: HTMLElement, child: HTMLNode) !void {
        if (!is_wasm) return;
        const console = Console.init();
        defer console.deinit();

        switch (child) {
            .element => |element| {
                _ = try self.ref.call(@import("js").Object, "appendChild", .{element.ref});
            },
            .text => |text| {
                _ = try self.ref.call(@import("js").Object, "appendChild", .{text.ref});
            },
        }
    }

    pub fn setAttribute(self: HTMLElement, name: []const u8, value: []const u8) void {
        if (!is_wasm) return;
        const real_js = @import("js");
        self.ref.call(void, "setAttribute", .{ real_js.string(name), real_js.string(value) }) catch {};
    }

    pub fn removeAttribute(self: HTMLElement, name: []const u8) void {
        if (!is_wasm) return;
        self.ref.call(void, "removeAttribute", .{@import("js").string(name)}) catch {};
    }

    /// Set a JavaScript property directly on the DOM node (not an attribute)
    /// Used for internal references like __zx_ref
    pub fn setProperty(self: HTMLElement, name: []const u8, value: anytype) void {
        if (!is_wasm) return;
        self.ref.set(name, value) catch {};
    }

    /// Get a JavaScript property from the DOM node
    pub fn getProperty(self: HTMLElement, comptime T: type, name: []const u8) !T {
        if (!is_wasm) return error.NotInBrowser;
        return try self.ref.get(T, name);
    }

    pub fn removeChild(self: HTMLElement, child: HTMLNode) !void {
        if (!is_wasm) return;
        switch (child) {
            .element => |element| {
                _ = try self.ref.call(@import("js").Object, "removeChild", .{element.ref});
            },
            .text => |text| {
                _ = try self.ref.call(@import("js").Object, "removeChild", .{text.ref});
            },
        }
    }

    pub fn replaceChild(self: HTMLElement, new_child: HTMLNode, old_child: HTMLNode) !void {
        if (!is_wasm) return;
        const new_ref = switch (new_child) {
            .element => |element| element.ref,
            .text => |text| text.ref,
        };
        const old_ref = switch (old_child) {
            .element => |element| element.ref,
            .text => |text| text.ref,
        };
        _ = try self.ref.call(@import("js").Object, "replaceChild", .{ new_ref, old_ref });
    }

    pub fn insertBefore(self: HTMLElement, new_child: HTMLNode, reference_child: ?HTMLNode) !void {
        if (!is_wasm) return;
        const new_ref = switch (new_child) {
            .element => |element| element.ref,
            .text => |text| text.ref,
        };
        if (reference_child) |ref_child| {
            const ref_ref = switch (ref_child) {
                .element => |element| element.ref,
                .text => |text| text.ref,
            };
            _ = try self.ref.call(@import("js").Object, "insertBefore", .{ new_ref, ref_ref });
        } else {
            _ = try self.ref.call(@import("js").Object, "insertBefore", .{ new_ref, null });
        }
    }
};

pub const HTMLText = struct {
    ref: JsObject,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, ref: JsObject) HTMLText {
        return .{
            .ref = ref,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: HTMLText) void {
        if (!is_wasm) return;
        self.ref.deinit();
    }

    pub fn setNodeValue(self: HTMLText, value: []const u8) void {
        if (!is_wasm) return;
        self.ref.set("nodeValue", @import("js").string(value)) catch {};
    }

    /// Set a JavaScript property directly on the text node
    pub fn setProperty(self: HTMLText, name: []const u8, value: anytype) void {
        if (!is_wasm) return;
        self.ref.set(name, value) catch {};
    }
};

pub const HTMLNode = union(enum) {
    element: HTMLElement,
    text: HTMLText,

    pub fn deinit(self: HTMLNode) void {
        switch (self) {
            .element => |element| element.deinit(),
            .text => |text| text.deinit(),
        }
    }
};

ref: JsObject,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Document {
    if (!is_wasm) return .{ .ref = {}, .allocator = allocator };
    const real_js = @import("js");
    const ref: real_js.Object = real_js.global.get(real_js.Object, "document") catch @panic("Document not found");
    return .{
        .ref = ref,
        .allocator = allocator,
    };
}

pub fn deinit(self: Document) void {
    if (!is_wasm) return;
    self.ref.deinit();
}

pub fn getElementById(self: Document, id: []const u8) error{ ElementNotFound, NotInBrowser }!HTMLElement {
    if (!is_wasm) return error.NotInBrowser;
    const real_js = @import("js");
    const ref: real_js.Object = self.ref.call(real_js.Object, "getElementById", .{real_js.string(id)}) catch {
        return error.ElementNotFound;
    };

    return HTMLElement.init(self.allocator, ref);
}

pub fn createElement(self: Document, tag: []const u8) HTMLElement {
    if (!is_wasm) return HTMLElement.init(self.allocator, {});
    const real_js = @import("js");
    const ref: real_js.Object = self.ref.call(real_js.Object, "createElement", .{real_js.string(tag)}) catch @panic("Failed to create element");

    return HTMLElement.init(self.allocator, ref);
}

pub fn createTextNode(self: Document, data: []const u8) HTMLText {
    if (!is_wasm) return HTMLText.init(self.allocator, {});
    const real_js = @import("js");
    const ref: real_js.Object = self.ref.call(real_js.Object, "createTextNode", .{real_js.string(data)}) catch @panic("Failed to create text");

    return HTMLText.init(self.allocator, ref);
}

/// Represents a hydration boundary marked by comment nodes <!--$id--> and <!--/$id-->
pub const CommentMarker = struct {
    start_comment: JsObject,
    end_comment: JsObject,
    parent: JsObject,
    allocator: std.mem.Allocator,

    /// Insert a new DOM node after the start comment (before existing content)
    pub fn insertContent(self: CommentMarker, node: HTMLNode) !void {
        if (!is_wasm) return;
        const real_js = @import("js");
        const node_ref = switch (node) {
            .element => |el| el.ref,
            .text => |txt| txt.ref,
        };
        // insertBefore(newNode, referenceNode) - insert before end comment
        _ = try self.parent.call(real_js.Object, "insertBefore", .{ node_ref, self.end_comment });
    }

    /// Clear all content between start and end markers
    pub fn clearContent(self: CommentMarker) void {
        if (!is_wasm) return;
        const real_js = @import("js");
        // Remove nodes between start and end comments
        while (true) {
            const next_sibling: real_js.Object = self.start_comment.get(real_js.Object, "nextSibling") catch break;
            // Check node type - comment nodes have nodeType === 8
            const node_type = next_sibling.get(i32, "nodeType") catch break;
            if (node_type == 8) {
                // It's a comment node - check if it's our end marker
                const text = next_sibling.getAlloc(real_js.String, self.allocator, "textContent") catch break;
                defer self.allocator.free(text);
                // End marker starts with '/'
                if (text.len > 0 and text[0] == '/') break;
            }
            _ = self.parent.call(real_js.Object, "removeChild", .{next_sibling}) catch break;
        }
    }

    /// Replace all content between markers with new node
    pub fn replaceContent(self: CommentMarker, node: HTMLNode) !void {
        self.clearContent();
        try self.insertContent(node);
    }
};

/// Find comment markers for a component ID (<!--$id--> and <!--/$id-->)
pub fn findCommentMarker(self: Document, id: []const u8) error{ MarkerNotFound, NotInBrowser }!CommentMarker {
    if (!is_wasm) return error.NotInBrowser;
    const real_js = @import("js");
    const allocator = self.allocator;

    // Build the marker strings we're looking for
    const start_marker = std.fmt.allocPrint(allocator, "${s}", .{id}) catch return error.MarkerNotFound;
    defer allocator.free(start_marker);
    const end_marker = std.fmt.allocPrint(allocator, "/${s}", .{id}) catch return error.MarkerNotFound;
    defer allocator.free(end_marker);

    // Use TreeWalker to find comment nodes
    // document.createTreeWalker(document.body, NodeFilter.SHOW_COMMENT)
    const body: real_js.Object = self.ref.get(real_js.Object, "body") catch return error.MarkerNotFound;
    const node_filter_show_comment: i32 = 128; // NodeFilter.SHOW_COMMENT
    const walker: real_js.Object = self.ref.call(real_js.Object, "createTreeWalker", .{ body, node_filter_show_comment }) catch return error.MarkerNotFound;

    var start_comment: ?real_js.Object = null;
    var end_comment: ?real_js.Object = null;

    // Iterate through all comment nodes
    while (true) {
        const node: real_js.Object = walker.call(real_js.Object, "nextNode", .{}) catch break;

        // Get comment text content
        const text = node.getAlloc(real_js.String, allocator, "textContent") catch continue;
        defer allocator.free(text);

        if (std.mem.eql(u8, text, start_marker)) {
            start_comment = node;
        } else if (std.mem.eql(u8, text, end_marker)) {
            end_comment = node;
            break; // Found both, stop searching
        }
    }

    if (start_comment) |start| {
        if (end_comment) |end| {
            // Get parent node
            const parent: real_js.Object = start.get(real_js.Object, "parentNode") catch return error.MarkerNotFound;
            return CommentMarker{
                .start_comment = start,
                .end_comment = end,
                .parent = parent,
                .allocator = allocator,
            };
        }
    }

    return error.MarkerNotFound;
}
