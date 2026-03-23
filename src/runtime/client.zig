const window = @import("client/window.zig");

pub const Event = @import("client/Event.zig");
const reactivity = @import("client/reactivity.zig");

// Legacy --- may get removed/renamed
pub const Document = window.Document;
pub const js = window.js;
pub const clearInterval = window.clearInterval;
pub const setInterval = window.setInterval;
pub const setTimeout = window.setTimeout;
pub const Console = window.Console;
pub const rerender = reactivity.rerender;
pub const eval = window.eval;
