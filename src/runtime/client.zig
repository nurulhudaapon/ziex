const window = @import("client/window.zig");

pub const Event = @import("client/Event.zig");
pub const jsx = @import("client/jsx.zig");

// Legacy --- may get removed/renamed
const reactivity = @import("client/reactivity.zig");
pub const Document = window.Document;
pub const js = window.js;
pub const clearInterval = window.clearInterval;
pub const setInterval = window.setInterval;
pub const setTimeout = window.setTimeout;
pub const Console = window.Console;
pub const rerender = reactivity.rerender;
pub const eval = window.eval;
