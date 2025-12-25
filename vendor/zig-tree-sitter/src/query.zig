const Language = @import("language.zig").Language;
const Node = @import("node.zig").Node;

const QueryError = enum(c_uint) {
    none,
    syntax,
    node_type,
    field,
    capture,
    structure,
    language,
};

// TODO: implement matches, captures & predicates

/// A set of patterns that match nodes in a syntax tree.
pub const Query = opaque {
    /// Create a new query from a string containing one or more S-expression
    /// patterns.
    ///
    /// The query is associated with a particular language, and can only be run
    /// on syntax nodes parsed with that language. References to Queries can be
    /// shared between multiple threads.
    ///
    /// If a pattern is invalid, this returns a `Query.Error` and writes
    /// the byte offset of the error to the `error_offset` parameter.
    ///
    /// Example:
    ///
    /// ```zig
    /// var error_offset: u32 = 0;
    /// const query = Query.create(language, "(identifier) @variable", &error_offset)
    ///     catch |err| std.debug.panic("{s} error at position {d}", . { @errorName(err), error_offset });
    /// ```
    pub fn create(language: *const Language, source: []const u8, error_offset: *u32) Error!*Query {
        var error_type: QueryError = .none;
        const query = ts_query_new(language, source.ptr, @intCast(source.len), error_offset, &error_type);
        return query orelse switch (error_type) {
            .syntax => error.InvalidSyntax,
            .node_type => error.InvalidNodeType,
            .field => error.InvalidField,
            .capture => error.InvalidCapture,
            .structure => error.InvalidStructure,
            .language => error.InvalidLanguage,
            else => unreachable,
        };
    }

    /// Destroy the query, freeing all of the memory that it used.
    pub fn destroy(self: *Query) void {
        ts_query_delete(self);
    }

    /// Get the byte offset where the given pattern starts in the query's source.
    pub fn startByteForPattern(self: *const Query, pattern_index: u32) u32 {
        return ts_query_start_byte_for_pattern(self, pattern_index);
    }

    /// Get the byte offset where the given pattern ends in the query's source.
    pub fn endByteForPattern(self: *const Query, pattern_index: u32) u32 {
        return ts_query_end_byte_for_pattern(self, pattern_index);
    }

    /// Get the number of patterns in the query.
    pub fn patternCount(self: *const Query) u32 {
        return ts_query_pattern_count(self);
    }

    /// Get the number of captures in the query.
    pub fn captureCount(self: *const Query) u32 {
        return ts_query_capture_count(self);
    }

    /// Get the number of literal strings in the query.
    pub fn stringCount(self: *const Query) u32 {
        return ts_query_string_count(self);
    }

    /// Check if the given pattern in the query has a single root node.
    pub fn isPatternRooted(self: *const Query, pattern_index: u32) bool {
        return ts_query_is_pattern_rooted(self, pattern_index);
    }

    /// Check if the given pattern in the query is non-local.
    ///
    /// A non-local pattern has multiple root nodes and can match within a
    /// repeating sequence of nodes, as specified by the grammar. Non-local
    /// patterns disable certain optimizations that would otherwise be possible
    /// when executing a query on a specific range of a syntax tree.
    pub fn isPatternNonLocal(self: *const Query, pattern_index: u32) bool {
        return ts_query_is_pattern_non_local(self, pattern_index);
    }

    /// Check if a given pattern is guaranteed to match once a given step is reached.
    ///
    /// The step is specified by its byte offset in the query's source code.
    pub fn isPatternGuaranteedAtStep(self: *const Query, byte_offset: u32) bool {
        return ts_query_is_pattern_guaranteed_at_step(self, byte_offset);
    }

    /// Get the name of one of the query's captures.
    ///
    /// Each capture is associated with a numeric id based
    /// on the order that it appeared in the query's source.
    pub fn captureNameForId(self: *const Query, index: u32) ?[]const u8 {
        var length: u32 = 0;
        const name = ts_query_capture_name_for_id(self, index, &length);
        return if (length > 0) name[0..length] else null;
    }

    /// Get the quantifier of the query's captures.
    pub fn captureQuantifierForId(self: *const Query, pattern_index: u32, capture_index: u32) ?Quantifier {
        if (pattern_index >= self.patternCount() or capture_index >= self.captureCount()) return null;
        return ts_query_capture_quantifier_for_id(self, pattern_index, capture_index);
    }

    /// Get the name of one of the query's literal strings.
    ///
    /// Each string is associated with a numeric id based
    /// on the order that it appeared in the query's source.
    pub fn stringValueForId(self: *const Query, index: u32) ?[]const u8 {
        var length: u32 = 0;
        if (self.stringCount() == 0) return null;
        const name = ts_query_string_value_for_id(self, index, &length);
        return if (length > 0) name[0..length] else null;
    }

    /// Disable a certain capture within a query.
    ///
    /// This prevents the capture from being returned in matches
    /// and also avoids any resource usage associated with recording
    /// the capture. Currently, there is no way to undo this.
    pub fn disableCapture(self: *Query, name: []const u8) void {
        ts_query_disable_capture(self, name.ptr, @intCast(name.len));
    }

    /// Disable a certain pattern within a query.
    ///
    /// This prevents the pattern from matching and removes most of the overhead
    /// associated with the pattern. Currently, there is no way to undo this.
    pub fn disablePattern(self: *Query, pattern_index: u32) void {
        ts_query_disable_pattern(self, pattern_index);
    }

    /// Get all of the predicates for the given pattern in the query.
    pub fn predicatesForPattern(self: *const Query, pattern_index: u32) []const PredicateStep {
        var count: u32 = 0;
        const predicates = ts_query_predicates_for_pattern(self, pattern_index, &count);
        return if (count > 0) predicates[0..count] else &.{};
    }

    /// The kind of error that occurred while creating a `Query`.
    pub const Error = error{
        InvalidSyntax,
        InvalidNodeType,
        InvalidField,
        InvalidCapture,
        InvalidStructure,
        InvalidLanguage,
    };

    /// A quantifier for captures.
    pub const Quantifier = enum(c_uint) {
        zero,
        zero_or_one,
        zero_or_more,
        one,
        one_or_more,
    };

    /// A particular `Node` that has been captured within a query.
    pub const Capture = extern struct {
        node: Node,
        index: u32,
    };

    /// A match that corresponds to a certain pattern in the query.
    pub const Match = struct {
        id: u32,
        pattern_index: u16,
        captures: []const Query.Capture,
    };

    /// A predicate step within a query.
    ///
    /// There are three types of steps:
    /// * `Done` - Steps with this type are *sentinels* that
    ///   represent the end of an individual predicate.
    /// * `Capture` - Steps with this type represent names of captures.
    ///   Their `value_id` can be used with the `captureNameForId()`
    ///   method to obtain the name of the capture.
    /// * `String` - Steps with this type represent literal strings.
    ///   Their `value_id` can be used with the `stringValueForId()`
    ///   method to obtain their string value.
    pub const PredicateStep = extern struct {
        type: enum(c_uint) { done, capture, string },
        value_id: u32,
    };
};

extern fn ts_query_new(
    language: ?*const Language,
    source: [*c]const u8,
    source_len: u32,
    error_offset: *u32,
    error_type: *QueryError,
) ?*Query;
extern fn ts_query_delete(self: *Query) void;
extern fn ts_query_pattern_count(self: *const Query) u32;
extern fn ts_query_capture_count(self: *const Query) u32;
extern fn ts_query_string_count(self: *const Query) u32;
extern fn ts_query_start_byte_for_pattern(self: *const Query, pattern_index: u32) u32;
extern fn ts_query_end_byte_for_pattern(self: *const Query, pattern_index: u32) u32;
extern fn ts_query_is_pattern_rooted(self: *const Query, pattern_index: u32) bool;
extern fn ts_query_is_pattern_non_local(self: *const Query, pattern_index: u32) bool;
extern fn ts_query_is_pattern_guaranteed_at_step(self: *const Query, byte_offset: u32) bool;
extern fn ts_query_capture_name_for_id(self: *const Query, index: u32, length: *u32) [*c]const u8;
extern fn ts_query_capture_quantifier_for_id(
    self: *const Query,
    pattern_index: u32,
    capture_index: u32,
) Query.Quantifier;
extern fn ts_query_string_value_for_id(self: *const Query, index: u32, length: *u32) [*c]const u8;
extern fn ts_query_disable_capture(self: *Query, name: [*c]const u8, length: u32) void;
extern fn ts_query_disable_pattern(self: *Query, pattern_index: u32) void;
extern fn ts_query_predicates_for_pattern(
    self: *const Query,
    pattern_index: u32,
    step_count: *u32,
) [*c]const Query.PredicateStep;
