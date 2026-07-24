//! Spinner indicator for long running operations

const std = @import("std");
const Io = std.Io;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Thread = std.Thread;

const styles = @import("spinner_styles.zig").styles;

const Spinner = @This();

pub const SpinnerStyles = union(enum) {
    pub const none = &.{""};
    pub const line = &.{ "- ", "\\ ", "| ", "/ " };
    pub const arc = &.{ "◜ ", "◠ ", "◝ ", "◞ ", "◡ ", "◟ " };
    pub const point = &.{ "∙∙∙ ", "●∙∙ ", "∙●∙ ", "∙∙● ", "∙∙∙ " };

    pub const dots = &.{ "⠋ ", "⠙ ", "⠹ ", "⠸ ", "⠼ ", "⠴ ", "⠦ ", "⠧ ", "⠇ ", "⠏ " };
    pub const dots2 = &.{ "⣼ ", "⣹ ", "⢻ ", "⠿ ", "⡟ ", "⣏ ", "⣧ ", "⣶ " };
    pub const dots_wide = &.{ "⠉⠉ ", "⠈⠙ ", "⠀⠹ ", "⠀⢸ ", "⠀⣰ ", "⢀⣠ ", "⣀⣀ ", "⣄⡀ ", "⣆⠀ ", "⡇⠀ ", "⠏⠀ ", "⠋⠁ " };
    pub const dots_circle = &.{ "⢎  ", "⠎⠁ ", "⠊⠑ ", "⠈⠱ ", " ⡱ ", "⢀⡰ ", "⢄⡠ ", "⢆⡀ " };
    pub const dots_8bit = &.{ "  ", "⠁ ", "⠂ ", "⠃ ", "⠄ ", "⠅ ", "⠆ ", "⠇ ", "⡀ ", "⡁ ", "⡂ ", "⡃ ", "⡄ ", "⡅ ", "⡆ ", "⡇ ", "⠈ ", "⠉ ", "⠊ ", "⠋ ", "⠌ ", "⠍ ", "⠎ ", "⠏ ", "⡈ ", "⡉ ", "⡊ ", "⡋ ", "⡌ ", "⡍ ", "⡎ ", "⡏ ", "⠐ ", "⠑ ", "⠒ ", "⠓ ", "⠔ ", "⠕ ", "⠖ ", "⠗ ", "⡐ ", "⡑ ", "⡒ ", "⡓ ", "⡔ ", "⡕ ", "⡖ ", "⡗ ", "⠘ ", "⠙ ", "⠚ ", "⠛ ", "⠜ ", "⠝ ", "⠞ ", "⠟ ", "⡘ ", "⡙ ", "⡚ ", "⡛ ", "⡜ ", "⡝ ", "⡞ ", "⡟ ", "⠠ ", "⠡ ", "⠢ ", "⠣ ", "⠤ ", "⠥ ", "⠦ ", "⠧ ", "⡠ ", "⡡ ", "⡢ ", "⡣ ", "⡤  ", "⡥ ", "⡦ ", "⡧ ", "⠨ ", "⠩ ", "⠪ ", "⠫ ", "⠬ ", "⠭ ", "⠮ ", "⠯ ", "⡨ ", "⡩ ", "⡪ ", "⡫ ", "⡬ ", "⡭ ", "⡮ ", "⡯ ", "⠰ ", "⠱ ", "⠲ ", "⠳ ", "⠴ ", "⠵ ", "⠶ ", "⠷ ", "⡰ ", "⡱ ", "⡲ ", "⡳ ", "⡴ ", "⡵ ", "⡶ ", "⡷ ", "⠸ ", "⠹ ", "⠺ ", "⠻ ", "⠼ ", "⠽ ", "⠾ ", "⠿ ", "⡸ ", "⡹ ", "⡺ ", "⡻ ", "⡼ ", "⡽ ", "⡾ ", "⡿ ", "⢀ ", "⢁ ", "⢂ ", "⢃ ", "⢄ ", "⢅ ", "⢆ ", "⢇ ", "⣀ ", "⣁ ", "⣂ ", "⣃ ", "⣄ ", "⣅ ", "⣆ ", "⣇ ", "⢈ ", "⢉ ", "⢊ ", "⢋ ", "⢌ ", "⢍ ", "⢎ ", "⢏ ", "⣈ ", "⣉ ", "⣊ ", "⣋ ", "⣌ ", "⣍ ", "⣎ ", "⣏ ", "⢐ ", "⢑ ", "⢒ ", "⢓ ", "⢔ ", "⢕ ", "⢖ ", "⢗ ", "⣐ ", "⣑ ", "⣒ ", "⣓ ", "⣔ ", "⣕ ", "⣖ ", "⣗ ", "⢘ ", "⢙ ", "⢚ ", "⢛ ", "⢜ ", "⢝ ", "⢞ ", "⢟ ", "⣘ ", "⣙ ", "⣚ ", "⣛ ", "⣜ ", "⣝ ", "⣞ ", "⣟ ", "⢠ ", "⢡ ", "⢢ ", "⢣ ", "⢤ ", "⢥ ", "⢦ ", "⢧ ", "⣠ ", "⣡ ", "⣢ ", "⣣ ", "⣤ ", "⣥ ", "⣦ ", "⣧ ", "⢨ ", "⢩ ", "⢪ ", "⢫ ", "⢬ ", "⢭ ", "⢮ ", "⢯ ", "⣨ ", "⣩ ", "⣪ ", "⣫ ", "⣬ ", "⣭ ", "⣮ ", "⣯ ", "⢰ ", "⢱ ", "⢲ ", "⢳ ", "⢴ ", "⢵ ", "⢶ ", "⢷ ", "⣰ ", "⣱ ", "⣲ ", "⣳ ", "⣴ ", "⣵ ", "⣶ ", "⣷ ", "⢸ ", "⢹ ", "⢺ ", "⢻ ", "⢼ ", "⢽ ", "⢾ ", "⢿ ", "⣸ ", "⣹ ", "⣺ ", "⣻ ", "⣼ ", "⣽ ", "⣾ ", "⣿ " };
    pub const sand = &.{ "⠁ ", "⠂ ", "⠄ ", "⡀ ", "⡈ ", "⡐ ", "⢁ ", "⡠ ", "⣀ ", "⣁ ", "⣂ ", "⣄ ", "⣌ ", "⣔ ", "⣤ ", "⣥ ", "⣦ ", "⣮ ", "⣶ ", "⣷ ", "⣿ ", "⡿ ", "⠿ ", "⢟ ", "⠟ ", "⡛ ", "⠛ ", "⠫ ", "⢋ ", "⠋ ", "⠍ ", "⡉ ", "⠉ ", "⠑ ", "⠡ " };
    pub const dots_scrolling = &.{ ".   ", "..  ", "... ", " .. ", "  . ", "    " };
    pub const flip = &.{ "_ ", "_ ", "_ ", "- ", "` ", "` ", "' ", "´ ", "- ", "_ ", "_ ", "_ " };

    pub const aesthetic = &.{ "▰▰▱▱▱▱▱ ", "▰▱▱▱▱▱▱ ", "▰▰▰▱▱▱▱ ", "▰▰▰▰▱▱▱ ", "▰▰▰▰▰▱▱ ", "▰▰▰▰▰▰▱ ", "▰▰▰▰▰▰▰ ", "▰▱▱▱▱▱▱ " };
    pub const bouncing_ball = &.{ "( ●    ) ", "(  ●   ) ", "(   ●  ) ", "(    ● ) ", "(     ●) ", "(    ● ) ", "(   ●  ) ", "(  ●   ) ", "( ●    ) ", "(●     ) " };
    pub const bouncing_bar = &.{ "[    ] ", "[=   ] ", "[==  ] ", "[=== ] ", "[ ===] ", "[  ==] ", "[   =] ", "[    ] ", "[   =] ", "[  ==] ", "[ ===] ", "[====] ", "[=== ] ", "[==  ] ", "[=   ] " };

    pub const toggle = &.{ "◍ ", "◌ " };
    pub const toggle2 = &.{ "□ ", "■ " };
    pub const noise = &.{ "▓ ", "▒ ", "░ " };
    pub const hamburger = &.{ "☱ ", "☲ ", "☴ " };
    pub const triangle = &.{ "◢ ", "◣ ", "◤ ", "◥ " };
    pub const box_bounce = &.{ "▌ ", "▀ ", "▐ ", "▄ " };
    pub const circle_halvess = &.{ "◐ ", "◓ ", "◑ ", "◒ " };
    pub const star = &.{ "✶ ", "✸ ", "✹ ", "✺ ", "✹ ", "✷ " };
    pub const grow_vertical = &.{ "  ", "▃ ", "▄ ", "▅ ", "▆ ", "▇ ", "▆ ", "▅ ", "▄ ", "▃ " };

    pub const earth = &.{ "🌍 ", "🌎 ", "🌏 " };
    pub const monkey = &.{ "🙈 ", "🙈 ", "🙉 ", "🙊 " };
    pub const speaker = &.{ "🔈 ", "🔉 ", "🔊 ", "🔉 " };
    pub const moon = &.{ "🌑 ", "🌒 ", "🌓 ", "🌔 ", "🌕 ", "🌖 ", "🌗 ", "🌘 " };
    pub const mindblown = &.{ "😐 ", "😐 ", "😮 ", "😮 ", "😦 ", "😦 ", "😧 ", "😧 ", "🤯 ", "💥 ", "✨ " };
    pub const clock = &.{ "🕛 ", "🕐 ", "🕑 ", "🕒 ", "🕓 ", "🕔 ", "🕕 ", "🕖 ", "🕗 ", "🕘 ", "🕙 ", "🕚 " };
    pub const weather = &.{ "☀️ ", "☀️ ", "☀️ ", "🌤 ", "⛅️ ", "🌥 ", "☁️ ", "🌧 ", "🌨 ", "🌧 ", "🌨 ", "🌧 ", "🌨 ", "⛈ ", "🌨 ", "🌧 ", "🌨 ", "☁️ ", "🌥 ", "⛅️ ", "🌤 ", "☀️ ", "☀️ " };
};

/// The state of an individual line managed by the spinner.
const State = enum {
    success,
    fail,
    info,
    /// A static line (e.g., a log) that is not part of the active spinner.
    preserve,
};

pub const SpinnerOptions = struct {
    frames: []const []const u8 = SpinnerStyles.dots,
    refresh_rate_ms: u64 = 80,
};

frames: []const []const u8,
refresh_rate_ms: u64,
message: []const u8,
is_spinning: std.atomic.Value(bool),
frame_index: std.atomic.Value(usize),
allocator: Allocator,
writer: *Io.Writer,
reader: *Io.Reader,
thread: ?Thread = null,
mutex: Io.Mutex = .init,

/// Initiate a new Spinner instance.
///
/// If no options are provided `init(..., .{})`, the default spinner will be dots with a 80ms refresh rate.
///
/// Use `Spinner.SpinnerStyles.[option]` or pass in `.{ .frames = " []const []const u8 " }` for a custom style.
///
pub fn init(writer: *Io.Writer, reader: *Io.Reader, allocator: Allocator, options: SpinnerOptions) Spinner {
    return Spinner{
        .writer = writer,
        .reader = reader,
        .allocator = allocator,
        .is_spinning = std.atomic.Value(bool).init(false),
        .frame_index = std.atomic.Value(usize).init(0),
        .refresh_rate_ms = options.refresh_rate_ms * std.time.ns_per_ms,
        .frames = options.frames,
        .message = "",
    };
}

pub fn deinit(self: *Spinner) void {
    self.stop();
    if (self.message.len > 0) {
        self.allocator.free(self.message);
    }
}

pub fn print(self: *Spinner, comptime format: []const u8, args: anytype) !void {
    self.writer.print("\r\x1b[2K", .{}) catch {};
    try self.writer.print(format, args);
}

pub fn start(self: *Spinner, comptime format: []const u8, args: anytype) !void {
    // if (self.is_spinning.load(.monotonic)) return; // already running

    const io = std.Io.Threaded.global_single_threaded.io();
    self.mutex.lockUncancelable(io);
    defer self.mutex.unlock(io);

    self.is_spinning.store(true, .release);

    if (self.message.len > 0) {
        self.allocator.free(self.message);
    }

    self.message = try std.fmt.allocPrint(self.allocator, format, args);

    self.thread = try Thread.spawn(.{}, spinLoop, .{self});
}

pub fn stop(self: *Spinner) void {
    if (!self.is_spinning.load(.monotonic)) return;
    self.is_spinning.store(false, .release);

    if (self.thread) |t| {
        t.join();
        self.thread = null;
    }
}

pub fn updateStyle(self: *Spinner, options: SpinnerOptions) void {
    const io = std.Io.Threaded.global_single_threaded.io();
    self.mutex.lockUncancelable(io);
    defer self.mutex.unlock(io);

    self.frame_index.store(0, .release);

    self.frames = options.frames;
    self.refresh_rate_ms = options.refresh_rate_ms * std.time.ns_per_ms;
}

pub fn updateMessage(self: *Spinner, comptime format: []const u8, args: anytype) !void {
    if (self.message.len > 0) {
        self.allocator.free(self.message);
    }
    self.message = try std.fmt.allocPrint(self.allocator, format, args);
}

pub fn succeed(self: *Spinner, comptime format: []const u8, args: anytype) !void {
    try self.finalize(.success, format, args);
}

pub fn fail(self: *Spinner, comptime format: []const u8, args: anytype) !void {
    try self.finalize(.fail, format, args);
}

pub fn info(self: *Spinner, comptime format: []const u8, args: anytype) !void {
    try self.finalize(.info, format, args);
}

pub fn preserve(self: *Spinner, comptime format: []const u8, args: anytype) !void {
    try self.finalize(.preserve, format, args);
}

fn finalize(self: *Spinner, state: State, comptime format: []const u8, args: anytype) !void {
    if (!self.is_spinning.load(.monotonic)) return;

    self.stop();

    const ticker = switch (state) {
        .success => styles.GREEN ++ "✔ " ++ styles.RESET,
        .fail => styles.RED ++ "✖ " ++ styles.RESET,
        .info => styles.BLUE ++ "i " ++ styles.RESET,
        .preserve => styles.DIM ++ "» " ++ styles.RESET,
    };

    if (self.message.len > 0) {
        self.allocator.free(self.message);
    }
    self.message = try std.fmt.allocPrint(self.allocator, format, args);

    self.writer.print("\r\x1b[2K", .{}) catch {};

    try self.writer.print("{s}{s}\n", .{ ticker, self.message });

    self.allocator.free(self.message);
    self.message = "";
}

fn spinLoop(self: *Spinner) void {
    const io = std.Io.Threaded.global_single_threaded.io();
    while (self.is_spinning.load(.acquire)) {
        self.writer.print("\r\x1b[2K", .{}) catch {};

        const index = self.frame_index.load(.acquire);
        self.writer.print("{s}{s}", .{ self.frames[index], self.message }) catch {};

        self.frame_index.store((index + 1) % self.frames.len, .release);

        io.sleep(std.Io.Duration.fromNanoseconds(@intCast(self.refresh_rate_ms)), .awake) catch {};
    }
    self.writer.print("\r\x1b[2K", .{}) catch {}; // Clear the line one final time on exit
}
