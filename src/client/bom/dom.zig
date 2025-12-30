pub const Document = @This();

pub const HTMLElement = struct {
    ref: js.Object,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, ref: js.Object) HTMLElement {
        return .{
            .ref = ref,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: HTMLElement) void {
        self.ref.deinit();
    }

    pub fn setInnerHTML(self: HTMLElement, html: []const u8) !void {
        return try self.ref.set("innerHTML", js.string(html));
    }

    pub fn appendChild(self: HTMLElement, child: HTMLNode) !void {
        const console = Console.init();
        defer console.deinit();

        switch (child) {
            .element => |element| {
                _ = try self.ref.call(js.Object, "appendChild", .{element.ref});
            },
            .text => |text| {
                _ = try self.ref.call(js.Object, "appendChild", .{text.ref});
            },
        }
    }

    pub fn setAttribute(self: HTMLElement, name: []const u8, value: []const u8) void {
        self.ref.call(void, "setAttribute", .{ js.string(name), js.string(value) }) catch {};
    }

    pub fn removeAttribute(self: HTMLElement, name: []const u8) void {
        self.ref.call(void, "removeAttribute", .{js.string(name)}) catch {};
    }

    /// Set a JavaScript property directly on the DOM node (not an attribute)
    /// Used for internal references like __zx_ref
    pub fn setProperty(self: HTMLElement, name: []const u8, value: anytype) void {
        self.ref.set(name, value) catch {};
    }

    /// Get a JavaScript property from the DOM node
    pub fn getProperty(self: HTMLElement, comptime T: type, name: []const u8) !T {
        return try self.ref.get(T, name);
    }

    pub fn removeChild(self: HTMLElement, child: HTMLNode) !void {
        switch (child) {
            .element => |element| {
                _ = try self.ref.call(js.Object, "removeChild", .{element.ref});
            },
            .text => |text| {
                _ = try self.ref.call(js.Object, "removeChild", .{text.ref});
            },
        }
    }

    pub fn replaceChild(self: HTMLElement, new_child: HTMLNode, old_child: HTMLNode) !void {
        const new_ref = switch (new_child) {
            .element => |element| element.ref,
            .text => |text| text.ref,
        };
        const old_ref = switch (old_child) {
            .element => |element| element.ref,
            .text => |text| text.ref,
        };
        _ = try self.ref.call(js.Object, "replaceChild", .{ new_ref, old_ref });
    }

    pub fn insertBefore(self: HTMLElement, new_child: HTMLNode, reference_child: ?HTMLNode) !void {
        const new_ref = switch (new_child) {
            .element => |element| element.ref,
            .text => |text| text.ref,
        };
        if (reference_child) |ref_child| {
            const ref_ref = switch (ref_child) {
                .element => |element| element.ref,
                .text => |text| text.ref,
            };
            _ = try self.ref.call(js.Object, "insertBefore", .{ new_ref, ref_ref });
        } else {
            _ = try self.ref.call(js.Object, "insertBefore", .{ new_ref, null });
        }
    }
};

pub const HTMLText = struct {
    ref: js.Object,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, ref: js.Object) HTMLText {
        return .{
            .ref = ref,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: HTMLText) void {
        self.ref.deinit();
    }

    pub fn setNodeValue(self: HTMLText, value: []const u8) void {
        self.ref.set("nodeValue", js.string(value)) catch {};
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

ref: js.Object,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Document {
    const ref: js.Object = js.global.get(js.Object, "document") catch @panic("Document not found");
    return .{
        .ref = ref,
        .allocator = allocator,
    };
}

pub fn deinit(self: Document) void {
    self.ref.deinit();
}

pub fn getElementById(self: Document, id: []const u8) error{ElementNotFound}!HTMLElement {
    const ref: js.Object = self.ref.call(js.Object, "getElementById", .{js.string(id)}) catch {
        return error.ElementNotFound;
    };

    return HTMLElement.init(self.allocator, ref);
}

pub fn createElement(self: Document, tag: []const u8) HTMLElement {
    const ref: js.Object = self.ref.call(js.Object, "createElement", .{js.string(tag)}) catch @panic("Failed to create element");

    return HTMLElement.init(self.allocator, ref);
}

pub fn createTextNode(self: Document, data: []const u8) HTMLText {
    const ref: js.Object = self.ref.call(js.Object, "createTextNode", .{js.string(data)}) catch @panic("Failed to create text");

    return HTMLText.init(self.allocator, ref);
}

const js = @import("js");
const std = @import("std");
const Console = @import("../bom.zig").Console;
