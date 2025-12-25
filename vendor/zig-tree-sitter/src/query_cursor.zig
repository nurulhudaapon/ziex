const Node = @import("node.zig").Node;
const Point = @import("point.zig").Point;
const Query = @import("query.zig").Query;

const QueryMatch = extern struct {
    id: u32,
    pattern_index: u16,
    capture_count: u16,
    captures: [*c]const Query.Capture,

    fn into(self: *QueryMatch) Query.Match {
        return .{
            .id = self.id,
            .pattern_index = self.pattern_index,
            .captures = if (self.capture_count == 0) &[_]Query.Capture{} else self.captures[0..self.capture_count],
        };
    }
};

/// A stateful object for executing a `Query` on a syntax `Tree`.
///
/// To use the query cursor, first call `exec()` to start
/// running a given query on a given syntax node. Then, there
/// are two options for consuming the results of the query:
/// 1. Repeatedly call `nextMatch()` to iterate over all of the *matches*
///    in the order that they were found. Each match contains the index of
///    the pattern that matched, and an array of captures. Because multiple
///    patterns can match the same set of nodes, one match may contain captures
///    that appear *before* some of the captures from a previous match.
/// 2. Repeatedly call `nextCapture()` to iterate over all of the individual
///    *captures* in the order that they appear. This is useful if you don't care
///    about which pattern matched, and just want a single ordered sequence of captures.
///
/// If you don't care about consuming all of the results, you can stop
/// calling `nextMatch()` or `nextCapture()` at any point. You can then
/// start executing another query on another node by calling `exec()` again.
pub const QueryCursor = opaque {
    /// Create a new cursor for executing a given query.
    pub fn create() *QueryCursor {
        return ts_query_cursor_new();
    }

    /// Destroy the query cursor, freeing all of the memory that it used.
    pub fn destroy(self: *QueryCursor) void {
        ts_query_cursor_delete(self);
    }

    /// Start a given query on a certain node.
    pub fn exec(self: *QueryCursor, query: *const Query, node: Node) void {
        ts_query_cursor_exec(self, query, node);
    }

    /// Start a given query on a certain node, with some options.
    pub fn execWithOptions(self: *QueryCursor, query: *const Query, node: Node, options: *const QueryCursor.Options) void {
        ts_query_cursor_exec_with_options(self, query, node, options);
    }

    /// Check if this cursor exceeded its maximum capacity for storing in-progress matches.
    ///
    /// If this capacity is exceeded, then the earliest-starting match will silently
    /// be dropped to make room for further matches. This maximum capacity is optional.
    /// By default, query cursors allow any number of pending matches, dynamically
    /// allocating new space for them as needed as the query is executed.
    pub fn didExceedMatchLimit(self: *const QueryCursor) bool {
        return ts_query_cursor_did_exceed_match_limit(self);
    }

    /// Get the cursor's maximum number of in-progress matches.
    pub fn getMatchLimit(self: *const QueryCursor) u32 {
        return ts_query_cursor_match_limit(self);
    }

    /// Set the cursor's maximum number of in-progress matches.
    pub fn setMatchLimit(self: *QueryCursor, limit: u32) void {
        ts_query_cursor_set_match_limit(self, limit);
    }

    /// Set the range of bytes in which the query will be executed.
    ///
    /// The query cursor will return matches that intersect with the
    /// given byte range. This means that a match may be returned
    /// even if some of its captures fall outside the specified range,
    /// as long as at least part of the match overlaps with the range.
    pub fn setByteRange(self: *QueryCursor, start_byte: u32, end_byte: u32) error{InvalidRange}!void {
        if (!ts_query_cursor_set_byte_range(self, start_byte, end_byte)) {
            return error.InvalidRange;
        }
    }

    /// Set the range of points in which the query will be executed.
    ///
    /// The query cursor will return matches that intersect with the
    /// given point range. This means that a match may be returned
    /// even if some of its captures fall outside the specified range,
    /// as long as at least part of the match overlaps with the range.
    pub fn setPointRange(self: *QueryCursor, start_point: Point, end_point: Point) error{InvalidRange}!void {
        if (!ts_query_cursor_set_point_range(self, start_point, end_point)) {
            return error.InvalidRange;
        }
    }

    /// Set the maximum start depth for a query cursor.
    ///
    /// This prevents cursors from exploring children nodes at a certain depth.
    /// Note that if a pattern includes many children, they will still be checked.
    ///
    /// The `0` max start depth value can be used as a special behavior and it
    /// helps to destructure a subtree by staying on a node and using captures
    /// for interested parts. Note that it will only limit the search depth for
    /// a pattern's root node, while other nodes that are parts of the pattern
    /// may be searched at any depth what defined by the pattern structure.
    ///
    /// Set to `0xFFFFFFFF` to remove the maximum start depth.
    pub fn setMaxStartDepth(self: *QueryCursor, max_start_depth: u32) void {
        ts_query_cursor_set_max_start_depth(self, max_start_depth);
    }

    /// Advance to the next match of the currently running query.
    pub fn nextMatch(self: *QueryCursor) ?Query.Match {
        var match: QueryMatch = undefined;
        return if (ts_query_cursor_next_match(self, &match)) match.into() else null;
    }

    /// Advance to the next capture of the currently running query.
    ///
    /// This returns a tuple where the first element is the
    /// index of the capture and the second is the match.
    pub fn nextCapture(self: *QueryCursor) ?struct { u32, Query.Match } {
        var index: u32 = 0;
        var match: QueryMatch = undefined;
        const result = ts_query_cursor_next_capture(self, &match, &index);
        return if (result) .{ index, match.into() } else null;
    }

    /// Remove a match from the query cursor.
    pub fn removeMatch(self: *QueryCursor, match_id: u32) void {
        ts_query_cursor_remove_match(self, match_id);
    }

    /// An object that represents the current state of the query cursor.
    pub const State = extern struct {
        payload: ?*anyopaque = null,
        current_byte_offset: u32,
    };

    /// An object which contains the query execution options.
    pub const Options = extern struct {
        payload: ?*anyopaque = null,
        /// A callback that receives the query state during execution.
        progress_callback: *const fn (state: State) callconv(.c) bool,
    };
};

pub extern fn ts_query_cursor_new() *QueryCursor;
pub extern fn ts_query_cursor_delete(self: *QueryCursor) void;
pub extern fn ts_query_cursor_exec(self: *QueryCursor, query: *const Query, node: Node) void;
pub extern fn ts_query_cursor_exec_with_options(
    self: *QueryCursor,
    query: *const Query,
    node: Node,
    options: *const QueryCursor.Options,
) void;
pub extern fn ts_query_cursor_did_exceed_match_limit(self: *const QueryCursor) bool;
pub extern fn ts_query_cursor_match_limit(self: *const QueryCursor) u32;
pub extern fn ts_query_cursor_set_match_limit(self: *QueryCursor, limit: u32) void;
pub extern fn ts_query_cursor_set_byte_range(self: *QueryCursor, start_byte: u32, end_byte: u32) bool;
pub extern fn ts_query_cursor_set_point_range(self: *QueryCursor, start_point: Point, end_point: Point) bool;
pub extern fn ts_query_cursor_set_max_start_depth(self: *QueryCursor, max_start_depth: u32) void;
pub extern fn ts_query_cursor_next_match(self: *QueryCursor, match: *QueryMatch) bool;
pub extern fn ts_query_cursor_next_capture(self: *QueryCursor, match: *QueryMatch, capture_index: *u32) bool;
pub extern fn ts_query_cursor_remove_match(self: *QueryCursor, match_id: u32) void;
