//! Bound form/event action with in-flight UX (`pending`) and settle hooks.
//!
//! ```zig
//! const create = ctx.action(handleCreate, .{ .reset = .on_success });
//! <form action={create}>
//!   <input name="title" disabled={create.pending} />
//!   <button disabled={create.pending}>{if (create.pending) "Adding…" else "Add"}</button>
//! </form>
//! ```

const EventHandler = @import("Handler.zig");

const ActionHandle = @This();

/// Put on `action={…}` (and similar). Framework stamps id via `handler`.
handler: EventHandler,
/// Snapshot at construction — true while a submission for this handle is in flight.
pending: bool,

pub const Outcome = EventHandler.ActionOutcome;
pub const Reset = EventHandler.ActionReset;

pub const Options = struct {
    on_settle: ?*const fn (Outcome) void = null,
    reset: Reset = .none,
};

/// Accept `{}` / `.{ .reset = .on_success }` / `.{ .on_settle = f }` without a fixed type.
pub fn normalizeOptions(opts: anytype) Options {
    var out: Options = .{};
    const Opts = @TypeOf(opts);
    if (comptime @hasField(Opts, "on_settle")) {
        out.on_settle = opts.on_settle;
    }
    if (comptime @hasField(Opts, "reset")) {
        out.reset = opts.reset;
    }
    return out;
}
