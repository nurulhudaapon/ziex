const zx = @import("zx");
const data = @import("../data.zig");

pub fn isDark() bool {
    return data.loadThemeIsDark();
}

pub fn apply(dark: bool) void {
    if (zx.platform.role != .client) return;

    const document = zx.client.Document.init(zx.allocator);
    defer document.deinit();

    const root = document.querySelector("html") catch return;
    defer root.deinit();

    root.setAttribute("data-theme", if (dark) "dark" else "light");
    root.setAttribute("style", if (dark) "color-scheme: dark;" else "color-scheme: light;");

    data.saveThemeIsDark(dark);
}

pub fn applyFromStorage() void {
    apply(isDark());
}

pub fn toggle() bool {
    const dark = !isDark();
    apply(dark);
    return dark;
}
