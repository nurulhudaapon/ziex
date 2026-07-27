const Handler = @This();

const std = @import("std");

pub const Zls = @import("Handler/Zls.zig");

pub const VTable = struct {};

vtable: VTable,

pub const failing = Handler{
    .vtable = .{},
};
