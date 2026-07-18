/// Centralized data for the devtool.
pub const ComponentMeta = struct {
    prop_items: []const StateItem = &[_]StateItem{},
    signal_items: []const StateItem = &[_]StateItem{},
    action_items: []const StateItem = &[_]StateItem{},
};

pub const Component = struct {
    id: []const u8 = "",
    name: []const u8,
    has_children: bool,
    children: []const Component,
    selected: bool = false,
    badge: []const u8 = "",
    meta: ?ComponentMeta = null,
    is_native: bool = false,
    /// CSS selector locating this node's root element in the inspected page,
    /// e.g. `div[class="bench-row"]`. For a component/text node it is the
    /// selector of its first descendant element (its rendered root). Empty when
    /// the node maps to no element.
    selector: []const u8 = "",
    /// Which match of `selector` (in document order) this node is — computed by
    /// counting prior elements with the same selector while walking the
    /// serialized tree in pre-order, which mirrors the DOM's document order.
    /// The devtool highlights `document.querySelectorAll(selector)[occurrence]`.
    occurrence: usize = 0,
};

pub const Route = struct {
    method: []const u8,
    path: []const u8,
};

pub const StateItem = zx.Component.Serializable.StateItem;

const storage_key = "zx-devtool-show-native-elements";
const tree_collapsed_key = "zx-devtool-tree-collapsed";
pub const host_storage_key = "zx-devtool-host-v2";
pub const path_storage_key = "zx-devtool-path-v1";
const settings_namespace = "ide/devtool/settings";
const theme_storage_key = "zx-devtool-theme-dark";

var _show_native_elements_loaded = false;
pub var show_native_elements: bool = true;
// Whether the entire component tree starts COLLAPSED in the tree UI.
// Controlled by the sidebar expand/collapse toggle button.
pub var tree_collapsed: bool = false;
pub var host: []const u8 = "localhost:3000";
pub var current_path: []const u8 = "/";

fn settingsKV() zx.Kv {
    return zx.kv.scoped(.settings_namespace);
}

pub fn loadSettings() bool {
    if (_show_native_elements_loaded) return true;
    show_native_elements = settingsKV().as(zx.allocator, storage_key, bool) catch null orelse true;
    tree_collapsed = settingsKV().as(zx.allocator, tree_collapsed_key, bool) catch null orelse false;
    host = settingsKV().get(zx.allocator, host_storage_key) catch null orelse host;
    current_path = settingsKV().get(zx.allocator, path_storage_key) catch null orelse current_path;
    _show_native_elements_loaded = true;
    return _show_native_elements_loaded;
}

pub fn saveSettings() void {
    settingsKV().putAs(storage_key, show_native_elements, .{}) catch {};
    settingsKV().putAs(tree_collapsed_key, tree_collapsed, .{}) catch {};
    settingsKV().put(host_storage_key, host, .{}) catch {};
}

pub fn loadThemeIsDark() bool {
    return settingsKV().as(zx.allocator, theme_storage_key, bool) catch null orelse true;
}

pub fn saveThemeIsDark(dark: bool) void {
    settingsKV().putAs(theme_storage_key, dark, .{}) catch {};
}

pub const components = [_]Component{
    .{
        .name = "App",
        .has_children = true,
        .selected = true,
        .badge = "fragment",
        .meta = ComponentMeta{
            .prop_items = &.{
                .{
                    .key = "replRef",
                    .value = "Object",
                    .meta = "(Ref)",
                    .children = &[_]StateItem{
                        .{ .key = "value", .value = "null", .meta = "" },
                        .{ .key = "__v_isRef", .value = "true", .meta = "" },
                    },
                },
                .{ .key = "AUTO_SAVE_STORAGE_KEY", .value = "\"zx-sfc-playground-auto-save\"", .meta = "" },
                .{ .key = "initAutoSave", .value = "true", .meta = "" },
                .{ .key = "autoSave", .value = "true", .meta = "(Ref)" },
                .{ .key = "productionMode", .value = "false", .meta = "(Ref)" },
                .{ .key = "zxVersion", .value = "null", .meta = "(Ref)" },
                .{
                    .key = "importMap",
                    .value = "Object",
                    .meta = "(Computed)",
                    .children = &[_]StateItem{
                        .{ .key = "imports", .value = "Object", .meta = "", .children = &[_]StateItem{
                            .{ .key = "zx", .value = "\"https://cdn.jsdelivr.net/npm/zx\"", .meta = "" },
                        } },
                    },
                },
                .{ .key = "hash", .value = "eNp9UU1LAzEQ/StjLqugXURPZVtQKaBgHFRW85FJ2p9vUBbKS2bWw7H93kqw1Q...", .meta = "" },
                .{
                    .key = "sfcOptions",
                    .value = "Object",
                    .meta = "(Computed)",
                    .children = &[_]StateItem{
                        .{ .key = "script", .value = "Object", .meta = "" },
                        .{ .key = "template", .value = "Object", .meta = "" },
                    },
                },
                .{
                    .key = "store",
                    .value = "Reactive",
                    .meta = "",
                    .children = &[_]StateItem{
                        .{ .key = "theme", .value = "\"dark\"", .meta = "(Ref)" },
                        .{ .key = "isVaporSupported", .value = "false", .meta = "(Ref)" },
                    },
                },
                .{
                    .key = "previewOptions",
                    .value = "Object",
                    .meta = "(Computed)",
                    .children = &[_]StateItem{
                        .{ .key = "headHTML", .value = "\"\"", .meta = "" },
                    },
                },
            },
            .signal_items = &.{
                .{ .key = "setVH", .value = "fn i()", .meta = "" },
                .{ .key = "toggleProdMode", .value = "fn p()", .meta = "" },
                .{ .key = "toggleSSR", .value = "fn f()", .meta = "" },
                .{ .key = "toggleAutoSave", .value = "fn m()", .meta = "" },
                .{ .key = "reloadPage", .value = "fn _()", .meta = "" },
                .{ .key = "toggleTheme", .value = "fn y(I)", .meta = "" },
                .{ .key = "Header", .value = "Header", .meta = "" },
                .{
                    .key = "Repl",
                    .value = "Object",
                    .meta = "",
                    .children = &[_]StateItem{
                        .{ .key = "setup", .value = "fn()", .meta = "" },
                        .{ .key = "render", .value = "fn()", .meta = "" },
                    },
                },
                .{
                    .key = "Monaco",
                    .value = "Object",
                    .meta = "",
                    .children = &[_]StateItem{
                        .{ .key = "editor", .value = "null", .meta = "(Ref)" },
                    },
                },
            },
            .action_items = &.{
                .{
                    .key = "replRef",
                    .value = "Object",
                    .meta = "",
                    .children = &[_]StateItem{
                        .{ .key = "$el", .value = "<div>", .meta = "" },
                    },
                },
            },
        },
        .children = &[_]Component{
            .{
                .name = "Header",
                .has_children = true,
                .meta = ComponentMeta{
                    .prop_items = &.{
                        .{ .key = "title", .value = "\"Ziex Playground\"", .meta = "(Ref)" },
                        .{ .key = "showNav", .value = "true", .meta = "(Ref)" },
                        .{ .key = "theme", .value = "\"dark\"", .meta = "(Ref)" },
                        .{
                            .key = "logo",
                            .value = "Object",
                            .meta = "(Ref)",
                            .children = &[_]StateItem{
                                .{ .key = "src", .value = "\"/assets/logo.svg\"", .meta = "" },
                                .{ .key = "alt", .value = "\"Ziex Logo\"", .meta = "" },
                            },
                        },
                        .{
                            .key = "navItems",
                            .value = "Object",
                            .meta = "(Computed)",
                            .children = &[_]StateItem{
                                .{ .key = "docs", .value = "\"/docs\"", .meta = "" },
                                .{ .key = "playground", .value = "\"/playground\"", .meta = "" },
                                .{ .key = "github", .value = "\"https://github.com\"", .meta = "" },
                            },
                        },
                        .{ .key = "isMenuOpen", .value = "false", .meta = "(Ref)" },
                    },
                    .signal_items = &.{
                        .{ .key = "toggleTheme", .value = "fn y(I)", .meta = "" },
                        .{ .key = "toggleMenu", .value = "fn m()", .meta = "" },
                        .{
                            .key = "VersionSelect",
                            .value = "Object",
                            .meta = "",
                            .children = &[_]StateItem{
                                .{ .key = "setup", .value = "fn()", .meta = "" },
                                .{ .key = "render", .value = "fn()", .meta = "" },
                            },
                        },
                    },
                    .action_items = &.{
                        .{
                            .key = "headerRef",
                            .value = "Object",
                            .meta = "",
                            .children = &[_]StateItem{
                                .{ .key = "$el", .value = "<header>", .meta = "" },
                            },
                        },
                    },
                },
                .children = &[_]Component{
                    .{ .name = "VersionSelect", .has_children = false, .children = &[_]Component{} },
                    .{ .name = "VersionSelect", .has_children = false, .children = &[_]Component{} },
                    .{ .name = "Sun", .has_children = false, .children = &[_]Component{} },
                    .{ .name = "Moon", .has_children = false, .children = &[_]Component{} },
                    .{ .name = "Share", .has_children = false, .children = &[_]Component{} },
                    .{ .name = "Reload", .has_children = false, .children = &[_]Component{} },
                    .{ .name = "Download", .has_children = false, .children = &[_]Component{} },
                    .{ .name = "GitHub", .has_children = false, .children = &[_]Component{} },
                },
            },
            .{
                .name = "Repl",
                .has_children = true,
                .children = &[_]Component{
                    .{
                        .name = "SplitPane",
                        .has_children = true,
                        .children = &[_]Component{
                            .{ .name = "Panes", .has_children = false, .children = &[_]Component{} },
                            .{ .name = "PanesTwo", .has_children = false, .children = &[_]Component{} },
                            .{ .name = "PanesThree", .has_children = false, .children = &[_]Component{} },
                        },
                    },
                },
            },
        },
    },
};

pub const routes = [_]Route{
    .{ .method = "GET", .path = "/" },
    .{ .method = "GET", .path = "/about" },
    .{ .method = "GET", .path = "/contact" },
    .{ .method = "GET", .path = "/api/users" },
    .{ .method = "POST", .path = "/api/users" },
    .{ .method = "GET", .path = "/api/posts" },
    .{ .method = "GET", .path = "/docs" },
    .{ .method = "GET", .path = "/settings" },
};

/// Tracks, per CSS selector, how many matching elements have been seen so far
/// while walking the serialized tree in pre-order (mirrors DOM document order).
pub const SelectorCounters = std.StringHashMap(usize);

/// Build a CSS selector that locates an element by tag plus its most specific
/// available attribute (`id`, else `class`). The same string is counted in the
/// devtool and queried in the page, so it must be derived identically here.
fn buildSelector(allocator: std.mem.Allocator, tag: zx.ElementTag, attributes: anytype) []const u8 {
    const tag_name = @tagName(tag);
    if (attributes) |attrs| {
        for (attrs) |a| {
            if (std.mem.eql(u8, a.name, "id")) {
                if (a.value) |v| if (v.len > 0)
                    return std.fmt.allocPrint(allocator, "{s}[id=\"{s}\"]", .{ tag_name, v }) catch tag_name;
            }
        }
        for (attrs) |a| {
            if (std.mem.eql(u8, a.name, "class")) {
                if (a.value) |v| if (v.len > 0)
                    return std.fmt.allocPrint(allocator, "{s}[class=\"{s}\"]", .{ tag_name, v }) catch tag_name;
            }
        }
    }
    return allocator.dupe(u8, tag_name) catch tag_name;
}

fn nextOccurrence(counters: *SelectorCounters, selector: []const u8) usize {
    const gop = counters.getOrPut(selector) catch return 0;
    if (!gop.found_existing) gop.value_ptr.* = 0;
    const occ = gop.value_ptr.*;
    gop.value_ptr.* = occ + 1;
    return occ;
}

pub fn fromSerializable(allocator: std.mem.Allocator, s: zx.Component.Serializable, path: []const u8, counters: *SelectorCounters) anyerror!Component {
    var name: []const u8 = "unknown";
    var badge: []const u8 = "";
    var is_native: bool = true;

    if (s.component) |c| {
        name = c;
        is_native = false;
    } else if (s.tag) |t| {
        name = @tagName(t);
    } else if (s.text) |_| {
        name = "text";
        badge = "text";
    }

    // Assign this node's own element locator (pre-order, before children) so
    // the occurrence numbering follows document order.
    var selector: []const u8 = "";
    var occurrence: usize = 0;
    if (s.tag) |t| {
        selector = buildSelector(allocator, t, s.attributes);
        occurrence = nextOccurrence(counters, selector);
    }

    var children: []const Component = &[_]Component{};
    if (s.children) |sc| {
        var children_mut = try allocator.alloc(Component, sc.len);
        for (sc, 0..) |child_s, i| {
            const child_path = try std.fmt.allocPrint(allocator, "{s}.{d}", .{ path, i });
            children_mut[i] = try fromSerializable(allocator, child_s, child_path, counters);
        }
        children = children_mut;
    }

    // A component/text node has no element of its own — it is located by its
    // first descendant element (its rendered root).
    if (s.tag == null) {
        for (children) |child| {
            if (child.selector.len > 0) {
                selector = child.selector;
                occurrence = child.occurrence;
                break;
            }
        }
    }

    var meta: ?ComponentMeta = null;
    if (s.props) |p| {
        var props_list = std.ArrayList(StateItem).empty;
        var signals_list = std.ArrayList(StateItem).empty;

        for (p) |item| {
            if (std.mem.eql(u8, item.meta, "(Ref)") or std.mem.eql(u8, item.meta, "(Computed)")) {
                try signals_list.append(allocator, item);
            } else {
                try props_list.append(allocator, item);
            }
        }

        meta = ComponentMeta{
            .prop_items = try props_list.toOwnedSlice(allocator),
            .signal_items = try signals_list.toOwnedSlice(allocator),
        };
    }

    return Component{
        .id = path,
        .name = name,
        .children = children,
        .has_children = children.len > 0,
        .badge = badge,
        .meta = meta,
        .is_native = is_native,
        .selector = selector,
        .occurrence = occurrence,
    };
}

pub fn fromSerializableSlice(allocator: std.mem.Allocator, sc: []const zx.Component.Serializable) anyerror![]const Component {
    var counters = SelectorCounters.init(allocator);
    defer counters.deinit();

    var children = try allocator.alloc(Component, sc.len);
    for (sc, 0..) |child_s, i| {
        const path = try std.fmt.allocPrint(allocator, "{d}", .{i});
        children[i] = try fromSerializable(allocator, child_s, path, &counters);
    }

    // Synthetic wrapper roots have no element of their own; locate them by the
    // first descendant element so hovering them still highlights the page.
    var root_sel: []const u8 = "";
    var root_occ: usize = 0;
    for (children) |child| {
        if (child.selector.len > 0) {
            root_sel = child.selector;
            root_occ = child.occurrence;
            break;
        }
    }

    var root_page = try allocator.alloc(Component, 1);
    root_page[0] = Component{
        .id = "0.root.layout.page",
        .name = "Page",
        .children = children,
        .has_children = children.len > 0,
        .badge = "",
        .meta = null,
        .selector = root_sel,
        .occurrence = root_occ,
    };

    var root_layout = try allocator.alloc(Component, 1);
    root_layout[0] = Component{
        .id = "0.root.layout",
        .name = "Layout",
        .children = root_page,
        .has_children = root_page.len > 0,
        .badge = "",
        .meta = null,
        .selector = root_sel,
        .occurrence = root_occ,
    };

    var root_component = try allocator.alloc(Component, 1);
    root_component[0] = Component{
        .id = "0.root",
        .name = "App",
        .children = root_layout,
        .has_children = root_layout.len > 0,
        .badge = "fragment",
        .meta = null,
        .selector = root_sel,
        .occurrence = root_occ,
    };

    return root_component;
}

const zx = @import("zx");
const std = @import("std");
