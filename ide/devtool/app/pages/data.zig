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
};

pub const Route = struct {
    method: []const u8,
    path: []const u8,
};

pub const StateItem = zx.Component.Serializable.StateItem;

const storage_key = "zx-devtool-show-native-elements";
pub const host_storage_key = "zx-devtool-host-v2";

var _show_native_elements_loaded = false;
pub var show_native_elements: bool = true;
pub var host: []const u8 = "localhost:3000";

pub fn loadSettings() void {
    if (_show_native_elements_loaded) return;
    _show_native_elements_loaded = true;
    // Returns 1.0 if stored "1" or not set, 0.0 if stored "0"
    const result = zx.client.eval(f64, "+(localStorage.getItem('" ++ storage_key ++ "')??1)") catch return;
    show_native_elements = result >= 1.0;

    // Read host from localStorage char-by-char using charCodeAt (eval with string return
    // is unsupported by jsz, but eval(f64) works fine — same pattern as native elements).
    const len_f = zx.client.eval(f64, "(localStorage.getItem('" ++ host_storage_key ++ "')||'').length") catch 0;
    const len: usize = @intFromFloat(len_f);
    if (len > 0 and len <= 256) {
        if (zx.client_allocator.alloc(u8, len)) |buf| {
            var all_ok = true;
            for (0..len) |i| {
                const script = std.fmt.allocPrint(
                    zx.client_allocator,
                    "(localStorage.getItem('" ++ host_storage_key ++ "')||'').charCodeAt({d})",
                    .{i},
                ) catch {
                    all_ok = false;
                    break;
                };
                defer zx.client_allocator.free(script);
                const code = zx.client.eval(f64, script) catch {
                    all_ok = false;
                    break;
                };
                buf[i] = @intFromFloat(code);
            }
            if (all_ok) host = buf;
        } else |_| {}
    }
}

pub fn saveSettings() void {
    const script = if (show_native_elements)
        "localStorage.setItem('" ++ storage_key ++ "','1');"
    else
        "localStorage.setItem('" ++ storage_key ++ "','0');";
    zx.client.eval(void, script) catch {};

    const h = std.fmt.allocPrint(zx.client_allocator, "localStorage.setItem('{s}','{s}');", .{ host_storage_key, host }) catch return;
    zx.client.eval(void, h) catch {};
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

pub fn fromSerializable(allocator: std.mem.Allocator, s: zx.Component.Serializable, path: []const u8) anyerror!Component {
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

    var children: []const Component = &[_]Component{};
    if (s.children) |sc| {
        var children_mut = try allocator.alloc(Component, sc.len);
        for (sc, 0..) |child_s, i| {
            const child_path = try std.fmt.allocPrint(allocator, "{s}.{d}", .{ path, i });
            children_mut[i] = try fromSerializable(allocator, child_s, child_path);
        }
        children = children_mut;
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
    };
}

pub fn fromSerializableSlice(allocator: std.mem.Allocator, sc: []const zx.Component.Serializable) anyerror![]const Component {
    var children = try allocator.alloc(Component, sc.len);
    for (sc, 0..) |child_s, i| {
        const path = try std.fmt.allocPrint(allocator, "{d}", .{i});
        children[i] = try fromSerializable(allocator, child_s, path);
    }

    var root_page = try allocator.alloc(Component, 1);
    root_page[0] = Component{
        .id = "0.root.layout.page",
        .name = "Page",
        .children = children,
        .has_children = children.len > 0,
        .badge = "",
        .meta = null,
    };

    var root_layout = try allocator.alloc(Component, 1);
    root_layout[0] = Component{
        .id = "0.root.layout",
        .name = "Layout",
        .children = root_page,
        .has_children = root_page.len > 0,
        .badge = "",
        .meta = null,
    };

    var root_component = try allocator.alloc(Component, 1);
    root_component[0] = Component{
        .id = "0.root",
        .name = "App",
        .children = root_layout,
        .has_children = root_layout.len > 0,
        .badge = "fragment",
        .meta = null,
    };

    return root_component;
}

const zx = @import("zx");
const std = @import("std");
