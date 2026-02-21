/// Centralized data for the devtool.
/// All pages should import from here so that counts and details stay in sync.
pub const version = "v1.0.0";

// ── Components ──────────────────────────────────────────────

pub const Component = struct {
    name: []const u8,
    has_children: bool,
    children: []const Component,
    selected: bool = false,
    badge: []const u8 = "",
};
pub const components = [_]Component{
    .{ .name = "App", .has_children = true, .selected = true, .badge = "fragment", .children = &[_]Component{
        .{ .name = "Header", .has_children = true, .children = &[_]Component{
            .{ .name = "VersionSelect", .has_children = false, .children = &[_]Component{} },
            .{ .name = "VersionSelect", .has_children = false, .children = &[_]Component{} },
            .{ .name = "Sun", .has_children = false, .children = &[_]Component{} },
            .{ .name = "Moon", .has_children = false, .children = &[_]Component{} },
            .{ .name = "Share", .has_children = false, .children = &[_]Component{} },
            .{ .name = "Reload", .has_children = false, .children = &[_]Component{} },
            .{ .name = "Download", .has_children = false, .children = &[_]Component{} },
            .{ .name = "GitHub", .has_children = false, .children = &[_]Component{} },
        } },
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
    } },
};

// ── Routes ──────────────────────────────────────────────────

pub const Route = struct {
    method: []const u8,
    path: []const u8,
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

// ── Comptime helpers ────────────────────────────────────────

pub fn countComponents(items: []const Component) comptime_int {
    var total: comptime_int = 0;
    for (items) |c| {
        total += 1 + countComponents(c.children);
    }
    return total;
}

pub const component_count = countComponents(&components);
pub const route_count = routes.len;

// ── Formatted strings (comptime) ────────────────────────────

pub const component_count_label = std.fmt.comptimePrint("{d} components", .{component_count});

pub const route_count_label = std.fmt.comptimePrint("{d} Routes", .{route_count});

// ── State items ─────────────────────────────────────────────

pub const StateItem = struct {
    key: []const u8,
    value: []const u8,
    meta: []const u8,
    children: []const StateItem = &[_]StateItem{},
};

pub const setup_items = [_]StateItem{
    .{ .key = "replRef", .value = "Object", .meta = "(Ref)", .children = &[_]StateItem{
        .{ .key = "value", .value = "null", .meta = "" },
        .{ .key = "__v_isRef", .value = "true", .meta = "" },
    } },
    .{ .key = "AUTO_SAVE_STORAGE_KEY", .value = "\"zx-sfc-playground-auto-save\"", .meta = "" },
    .{ .key = "initAutoSave", .value = "true", .meta = "" },
    .{ .key = "autoSave", .value = "true", .meta = "(Ref)" },
    .{ .key = "productionMode", .value = "false", .meta = "(Ref)" },
    .{ .key = "zxVersion", .value = "null", .meta = "(Ref)" },
    .{ .key = "importMap", .value = "Object", .meta = "(Computed)", .children = &[_]StateItem{
        .{ .key = "imports", .value = "Object", .meta = "", .children = &[_]StateItem{
            .{ .key = "zx", .value = "\"https://cdn.jsdelivr.net/npm/zx\"", .meta = "" },
        } },
    } },
    .{ .key = "hash", .value = "eNp9UU1LAzEQ/StjLqugXURPZVtQKaBgHFRW85FJ2p9vUBbKS2bWw7H93kqw1Q...", .meta = "" },
    .{ .key = "sfcOptions", .value = "Object", .meta = "(Computed)", .children = &[_]StateItem{
        .{ .key = "script", .value = "Object", .meta = "" },
        .{ .key = "template", .value = "Object", .meta = "" },
    } },
    .{ .key = "store", .value = "Reactive", .meta = "", .children = &[_]StateItem{
        .{ .key = "theme", .value = "\"dark\"", .meta = "(Ref)" },
        .{ .key = "isVaporSupported", .value = "false", .meta = "(Ref)" },
    } },
    .{ .key = "previewOptions", .value = "Object", .meta = "(Computed)", .children = &[_]StateItem{
        .{ .key = "headHTML", .value = "\"\"", .meta = "" },
    } },
};

pub const setup_other_items = [_]StateItem{
    .{ .key = "setVH", .value = "fn i()", .meta = "" },
    .{ .key = "toggleProdMode", .value = "fn p()", .meta = "" },
    .{ .key = "toggleSSR", .value = "fn f()", .meta = "" },
    .{ .key = "toggleAutoSave", .value = "fn m()", .meta = "" },
    .{ .key = "reloadPage", .value = "fn _()", .meta = "" },
    .{ .key = "toggleTheme", .value = "fn y(I)", .meta = "" },
    .{ .key = "Header", .value = "Header", .meta = "" },
    .{ .key = "Repl", .value = "Object", .meta = "", .children = &[_]StateItem{
        .{ .key = "setup", .value = "fn()", .meta = "" },
        .{ .key = "render", .value = "fn()", .meta = "" },
    } },
    .{ .key = "Monaco", .value = "Object", .meta = "", .children = &[_]StateItem{
        .{ .key = "editor", .value = "null", .meta = "(Ref)" },
    } },
};

pub const template_refs_items = [_]StateItem{
    .{ .key = "replRef", .value = "Object", .meta = "", .children = &[_]StateItem{
        .{ .key = "$el", .value = "<div>", .meta = "" },
    } },
};

const std = @import("std");
