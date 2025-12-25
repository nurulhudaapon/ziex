const std = @import("std");

const Language = @import("language.zig").Language;

/// A stateful object that is used to look up symbols valid in a specific parse state.
pub const LookaheadIterator = opaque {
    /// Destroy the lookahead iterator, freeing all the memory used.
    pub fn destroy(self: *LookaheadIterator) void {
        ts_lookahead_iterator_delete(self);
    }

    /// Get the current language of the lookahead iterator.
    pub fn language(self: *const LookaheadIterator) *const Language {
        return ts_lookahead_iterator_language(self);
    }

    /// Get the current symbol of the lookahead iterator.
    pub fn currentSymbol(self: *const LookaheadIterator) u16 {
        return ts_lookahead_iterator_current_symbol(self);
    }

    /// Get the current symbol name of the lookahead iterator.
    pub fn currentSymbolName(self: *const LookaheadIterator) []const u8 {
        return std.mem.span(ts_lookahead_iterator_current_symbol_name(self));
    }

    /// Advance the lookahead iterator to the next symbol.
    ///
    /// This returns `true` if there is a new symbol and `false` otherwise.
    pub fn next(self: *LookaheadIterator) bool {
        return ts_lookahead_iterator_next(self);
    }

    /// Reset the lookahead iterator.
    ///
    /// This returns `true` if the language was set successfully and `false`
    /// otherwise.
    pub fn reset(self: *LookaheadIterator, lang: *const Language, state: u16) bool {
        return ts_lookahead_iterator_reset(self, lang, state);
    }

    /// Reset the lookahead iterator to another state.
    ///
    /// This returns `true` if the iterator was reset to the given state and
    /// `false` otherwise.
    pub fn resetState(self: *LookaheadIterator, state: u16) bool {
        return ts_lookahead_iterator_reset_state(self, state);
    }
};

extern fn ts_lookahead_iterator_current_symbol(self: *const LookaheadIterator) u16;
extern fn ts_lookahead_iterator_current_symbol_name(self: *const LookaheadIterator) [*:0]const u8;
extern fn ts_lookahead_iterator_delete(self: *LookaheadIterator) void;
extern fn ts_lookahead_iterator_language(self: ?*const LookaheadIterator) *const Language;
extern fn ts_lookahead_iterator_next(self: *LookaheadIterator) bool;
extern fn ts_lookahead_iterator_reset(self: *LookaheadIterator, language: *const Language, state: u16) bool;
extern fn ts_lookahead_iterator_reset_state(self: *LookaheadIterator, state: u16) bool;
