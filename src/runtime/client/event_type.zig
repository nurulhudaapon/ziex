const std = @import("std");

pub const EventType = enum(u8) {
    click,
    dblclick,
    input,
    change,
    submit,
    focus,
    blur,
    keydown,
    keyup,
    keypress,
    mouseenter,
    mouseleave,
    mousedown,
    mouseup,
    mousemove,
    touchstart,
    touchend,
    touchmove,
    scroll,
    wheel,
    pointerdown,
    pointermove,
    pointerup,
    pointercancel,
    pointerenter,
    pointerleave,
    lostpointercapture,

    pub fn fromAttributeName(name: []const u8) ?EventType {
        if (name.len < 3 or !std.mem.startsWith(u8, name, "on")) return null;
        return std.meta.stringToEnum(EventType, name[2..]);
    }

    pub fn domEventName(self: EventType) []const u8 {
        return switch (self) {
            .focus => "focusin",
            .blur => "focusout",
            else => @tagName(self),
        };
    }

    pub fn isHighFreq(self: EventType) bool {
        return switch (self) {
            .mousemove, .pointermove, .wheel, .scroll, .touchmove => true,
            else => false,
        };
    }
};
