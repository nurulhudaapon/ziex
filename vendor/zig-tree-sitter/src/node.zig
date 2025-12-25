const std = @import("std");

const alloc = @import("alloc.zig");
const InputEdit = @import("tree.zig").InputEdit;
const Language = @import("language.zig").Language;
const Point = @import("point.zig").Point;
const Range = @import("point.zig").Range;
const Tree = @import("tree.zig").Tree;
const TreeCursor = @import("tree_cursor.zig").TreeCursor;

/// A single node within a syntax tree.
pub const Node = extern struct {
    /// **Internal.** The context of the node.
    context: [4]u32,

    /// The ID of the node.
    ///
    /// Within any given syntax tree, no two nodes have the same ID.
    /// However, if a new tree is created based on an older tree,
    /// and a node from the old tree is reused in the process,
    /// then that node will have the same ID in both trees.
    id: *const anyopaque,

    /// **Internal.** The syntax tree this node belongs to.
    tree: *const Tree,

    /// Check if two nodes are identical.
    pub fn eql(self: Node, other: Node) bool {
        return ts_node_eq(self, other);
    }

    /// Get this node's type as a numerical id.
    pub fn kindId(self: Node) u16 {
        return ts_node_symbol(self);
    }

    /// Get the node's type as a numerical id as it appears in the grammar
    /// ignoring aliases.
    pub fn grammarId(self: Node) u16 {
        return ts_node_grammar_symbol(self);
    }

    /// Get this node's type as a string.
    pub fn kind(self: Node) []const u8 {
        return std.mem.span(ts_node_type(self));
    }

    /// Get this node's symbol name as it appears in the grammar ignoring
    /// aliases as a string.
    pub fn grammarKind(self: Node) []const u8 {
        return std.mem.span(ts_node_grammar_type(self));
    }

    /// Get the language that was used to parse this node's syntax tree.
    pub fn getLanguage(self: Node) *const Language {
        return ts_node_language(self);
    }

    /// Check if this node is *named*.
    ///
    /// Named nodes correspond to named rules in the grammar,
    /// whereas *anonymous* nodes correspond to string literals.
    pub fn isNamed(self: Node) bool {
        return ts_node_is_named(self);
    }

    /// Check if this node is *extra*.
    ///
    /// Extra nodes represent things like comments, which are not required by the
    /// grammar, but can appear anywhere.
    pub fn isExtra(self: Node) bool {
        return ts_node_is_extra(self);
    }

    /// Check if the node has been edited.
    pub fn hasChanges(self: Node) bool {
        return ts_node_has_changes(self);
    }

    /// Check if this node represents a syntax error or contains any syntax
    /// errors anywhere within it.
    pub fn hasError(self: Node) bool {
        return ts_node_has_error(self);
    }

    /// Check if this node represents a syntax error.
    ///
    /// Syntax errors represent parts of the code that could not be incorporated
    /// into a valid syntax tree.
    pub fn isError(self: Node) bool {
        return ts_node_is_error(self);
    }

    /// Check if this node is *missing*.
    ///
    /// Missing nodes are inserted by the parser in order to recover from
    /// certain kinds of syntax errors.
    pub fn isMissing(self: Node) bool {
        return ts_node_is_missing(self);
    }

    /// Get this node's parse state.
    pub fn parseState(self: Node) u16 {
        return ts_node_parse_state(self);
    }

    /// Get the parse state after this node.
    pub fn nextParseState(self: Node) u16 {
        return ts_node_next_parse_state(self);
    }

    /// Get the byte offset where this node starts.
    pub fn startByte(self: Node) u32 {
        return ts_node_start_byte(self);
    }

    /// Get the byte offset where this node ends.
    pub fn endByte(self: Node) u32 {
        return ts_node_end_byte(self);
    }

    /// Get this node's start position in terms of rows and columns.
    pub fn startPoint(self: Node) Point {
        return ts_node_start_point(self);
    }

    /// Get this node's end position in terms of rows and columns.
    pub fn endPoint(self: Node) Point {
        return ts_node_end_point(self);
    }

    /// Get the range of source code that this node represents, both in terms of
    /// raw bytes and of row/column coordinates.
    pub fn range(self: Node) Range {
        return .{
            .start_byte = self.startByte(),
            .end_byte = self.endByte(),
            .start_point = self.startPoint(),
            .end_point = self.endPoint(),
        };
    }

    /// Get the node's child at the given index, where zero represents the first
    /// child.
    ///
    /// This method is fairly fast, but its cost is technically log(i), so if
    /// you might be iterating over a long list of children, you should use
    /// `Node.children()` instead.
    pub fn child(self: Node, child_index: u32) ?Node {
        return ts_node_child(self, child_index).orNull();
    }

    /// Get this node's number of children.
    pub fn childCount(self: Node) u32 {
        return ts_node_child_count(self);
    }

    /// Get this node's *named* child at the given index.
    ///
    /// See also `Node.isNamed()`.
    /// This method is fairly fast, but its cost is technically log(i), so if
    /// you might be iterating over a long list of children, you should use
    /// `Node.namedChildren()` instead.
    pub fn namedChild(self: Node, child_index: u32) ?Node {
        return ts_node_named_child(self, child_index).orNull();
    }

    /// Get this node's number of *named* children.
    ///
    /// See also `Node.isNamed()`.
    pub fn namedChildCount(self: Node) u32 {
        return ts_node_named_child_count(self);
    }

    /// Get the first child with the given field name.
    ///
    /// If multiple children may have the same field name, access them using
    /// `Node.children_by_field_name`.
    pub fn childByFieldName(self: Node, name: []const u8) ?Node {
        return ts_node_child_by_field_name(self, name.ptr, @intCast(name.len)).orNull();
    }

    /// Get this node's child with the given numerical field id.
    ///
    /// See also `Node.childByFieldName()`. You can
    /// convert a field name to an id using `Language.fieldIdForName()`.
    pub fn childByFieldId(self: Node, field_id: u16) ?Node {
        return ts_node_child_by_field_id(self, field_id).orNull();
    }

    /// Get the field name of this node's child at the given index.
    pub fn fieldNameForChild(self: Node, child_index: u32) ?[]const u8 {
        return if (ts_node_field_name_for_child(self, child_index)) |name| std.mem.span(name) else null;
    }

    /// Get the field name of this node's named child at the given index.
    pub fn fieldNameForNamedChild(self: Node, child_index: u32) ?[]const u8 {
        return if (ts_node_field_name_for_named_child(self, child_index)) |name| std.mem.span(name) else null;
    }

    /// Iterate over this node's children.
    ///
    /// A `TreeCursor` is used to retrieve the children efficiently. Obtain
    /// a `TreeCursor` by calling `Tree.walk()` or `Node.walk()`. To avoid
    /// unnecessary allocations, you should reuse the same cursor for
    /// subsequent calls to this method.
    ///
    /// If you're walking the tree recursively, you may want to use the
    /// `TreeCursor` APIs directly instead.
    ///
    /// The caller is responsible for freeing the resulting array using `std.ArrayList.deinit`.
    pub fn children(self: Node, cursor: *TreeCursor, allocator: std.mem.Allocator) ![]Node {
        var result = try std.ArrayList(Node).initCapacity(allocator, self.childCount());
        errdefer result.deinit(allocator);

        cursor.reset(self);
        if (!cursor.gotoFirstChild()) {
            return try result.toOwnedSlice(allocator);
        }

        try result.append(allocator, cursor.currentNode());
        while (cursor.gotoNextSibling()) {
            result.appendAssumeCapacity(cursor.currentNode());
        }

        return result.toOwnedSlice();
    }

    /// Iterate over this node's named children.
    ///
    /// See also `Node.children()`.
    ///
    /// The caller is responsible for freeing the resulting array using `std.ArrayList.deinit`.
    pub fn namedChildren(self: Node, cursor: *TreeCursor, allocator: std.mem.Allocator) ![]Node {
        var result = try std.ArrayList(Node).initCapacity(allocator, self.namedChildCount());
        errdefer result.deinit(allocator);

        cursor.reset(self);
        if (!cursor.gotoFirstChild()) {
            return try result.toOwnedSlice(allocator);
        }

        while (true) {
            var node = cursor.currentNode();
            if (node.isNamed()) {
                result.appendAssumeCapacity(node);
            }
            if (!cursor.gotoNextSibling()) break;
        }

        return try result.toOwnedSlice(allocator);
    }

    /// Iterate over this node's children with a given field name.
    ///
    /// See also `Node.children()`.
    ///
    /// The caller owns the memory.
    pub fn childrenByFieldName(self: Node, field_name: []const u8, cursor: *TreeCursor, allocator: std.mem.Allocator) ![]Node {
        const field_id = self.getLanguage().fieldIdForName(field_name);
        return self.childrenByFieldId(field_id, cursor, allocator);
    }

    /// Iterate over this node's children with a given field id.
    ///
    /// See also `Node.childrenByFieldName()`.
    ///
    /// The caller owns the memory.
    pub fn childrenByFieldId(self: Node, field_id: u16, cursor: *TreeCursor, allocator: std.mem.Allocator) ![]Node {
        var result = std.ArrayList(Node).empty;
        errdefer result.deinit(allocator);

        cursor.reset(self);
        if (field_id == 0 or !cursor.gotoFirstChild()) {
            return try result.toOwnedSlice(allocator);
        }

        while (true) {
            if (cursor.currentFieldId() == field_id) {
                try result.append(allocator, cursor.currentNode());
            }
            if (!cursor.gotoNextSibling()) {
                break;
            }
        }

        return result.toOwnedSlice();
    }

    /// Get this node's immediate parent.
    /// Prefer `Node.child_with_descendant()` for iterating over this node's ancestors.
    pub fn parent(self: Node) ?Node {
        return ts_node_parent(self).orNull();
    }

    /// Get the node that contains `descendant`.
    ///
    /// Note that this can return `descendant` itself.
    pub fn childWithDescendant(self: Node, descendant: Node) ?Node {
        return ts_node_child_with_descendant(self, descendant).orNull();
    }

    /// Get this node's next sibling.
    pub fn nextSibling(self: Node) ?Node {
        return ts_node_next_sibling(self).orNull();
    }

    /// Get this node's previous sibling.
    pub fn prevSibling(self: Node) ?Node {
        return ts_node_prev_sibling(self).orNull();
    }

    /// Get this node's next named sibling.
    pub fn nextNamedSibling(self: Node) ?Node {
        return ts_node_next_named_sibling(self).orNull();
    }

    /// Get this node's previous named sibling.
    pub fn prevNamedSibling(self: Node) ?Node {
        return ts_node_prev_named_sibling(self).orNull();
    }

    /// Get this node's first child that contains or starts after the given byte offset.
    pub fn firstChildForByte(self: Node, byte: u32) ?Node {
        return ts_node_first_child_for_byte(self, byte).orNull();
    }

    /// Get this node's first *named* child that contains or starts after the given byte offset.
    pub fn firstNamedChildForByte(self: Node, byte: u32) ?Node {
        return ts_node_first_named_child_for_byte(self, byte).orNull();
    }

    /// Get the node's number of descendants, including one for the node itself.
    pub fn descendantCount(self: Node) u32 {
        return ts_node_descendant_count(self);
    }

    /// Get the smallest node within this node that spans the given byte range.
    pub fn descendantForByteRange(self: Node, start: u32, end: u32) ?Node {
        return ts_node_descendant_for_byte_range(self, start, end).orNull();
    }

    /// Get the smallest *named* node within this node that spans the given byte range.
    pub fn namedDescendantForByteRange(self: Node, start: u32, end: u32) ?Node {
        return ts_node_named_descendant_for_byte_range(self, start, end).orNull();
    }

    /// Get the smallest node within this node that spans the given point range.
    pub fn descendantForPointRange(self: Node, start: Point, end: Point) ?Node {
        return ts_node_descendant_for_point_range(self, start, end).orNull();
    }

    /// Get the smallest *named* node within this node that spans the given point range.
    pub fn namedDescendantForPointRange(self: Node, start: Point, end: Point) ?Node {
        return ts_node_named_descendant_for_point_range(self, start, end).orNull();
    }

    /// Get an S-expression representing the node.
    ///
    /// The caller owns the memory.
    pub fn toSexp(self: Node, allocator: std.mem.Allocator) ![]u8 {
        const string = ts_node_string(self);
        defer alloc.free_fn()(@ptrCast(@constCast(string)));
        return try allocator.dupe(u8, std.mem.span(string));
    }

    /// Create a new `TreeCursor` starting from this node.
    ///
    /// Note that the given node is considered the root of the cursor,
    /// and the cursor cannot walk outside this node.
    pub fn walk(self: Node) TreeCursor {
        return ts_tree_cursor_new(self);
    }

    /// Edit this node to keep it in-sync with source code that has been edited.
    ///
    /// This function is only rarely needed. When you edit a syntax tree with
    /// the `Tree.edit()` method, all of the nodes that you retrieve from
    /// the tree afterward will already reflect the edit. You only need to
    /// use `Node.edit()` when you have a specific `Node` instance that
    /// you want to keep and continue to use after an edit.
    pub fn edit(self: *Node, input_edit: InputEdit) void {
        ts_node_edit(self, &input_edit);
    }

    /// Format the node as a string.
    pub fn format(self: Node, writer: *std.Io.Writer) !void {
        try writer.print(
            "Node(id=0x{x}, kind={s}, start={d}, end={d})",
            .{
                @intFromPtr(self.id),
                self.kind(),
                self.startByte(),
                self.endByte(),
            },
        );
    }

    fn orNull(self: Node) ?Node {
        return if (!ts_node_is_null(self)) self else null;
    }
};

extern fn ts_node_child(self: Node, child_index: u32) Node;
extern fn ts_node_child_by_field_id(self: Node, field_id: u16) Node;
extern fn ts_node_child_by_field_name(self: Node, name: [*]const u8, name_length: u32) Node;
extern fn ts_node_child_containing_descendant(self: Node, descendant: Node) Node;
extern fn ts_node_child_with_descendant(self: Node, descendant: Node) Node;
extern fn ts_node_child_count(self: Node) u32;
extern fn ts_node_descendant_count(self: Node) u32;
extern fn ts_node_descendant_for_byte_range(self: Node, start: u32, end: u32) Node;
extern fn ts_node_descendant_for_point_range(self: Node, start: Point, end: Point) Node;
extern fn ts_node_edit(self: *Node, edit: *const InputEdit) void;
extern fn ts_node_end_byte(self: Node) u32;
extern fn ts_node_end_point(self: Node) Point;
extern fn ts_node_eq(self: Node, other: Node) bool;
extern fn ts_node_field_name_for_child(self: Node, child_index: u32) ?[*:0]const u8;
extern fn ts_node_field_name_for_named_child(self: Node, named_child_index: u32) ?[*:0]const u8;
extern fn ts_node_first_child_for_byte(self: Node, byte: u32) Node;
extern fn ts_node_first_named_child_for_byte(self: Node, byte: u32) Node;
extern fn ts_node_grammar_symbol(self: Node) u16;
extern fn ts_node_grammar_type(self: Node) [*:0]const u8;
extern fn ts_node_has_changes(self: Node) bool;
extern fn ts_node_has_error(self: Node) bool;
extern fn ts_node_is_error(self: Node) bool;
extern fn ts_node_is_extra(self: Node) bool;
extern fn ts_node_is_missing(self: Node) bool;
extern fn ts_node_is_named(self: Node) bool;
extern fn ts_node_is_null(self: Node) bool;
extern fn ts_node_language(self: Node) *const Language;
extern fn ts_node_named_child(self: Node, child_index: u32) Node;
extern fn ts_node_named_child_count(self: Node) u32;
extern fn ts_node_named_descendant_for_byte_range(self: Node, start: u32, end: u32) Node;
extern fn ts_node_named_descendant_for_point_range(self: Node, start: Point, end: Point) Node;
extern fn ts_node_next_named_sibling(self: Node) Node;
extern fn ts_node_next_parse_state(self: Node) u16;
extern fn ts_node_next_sibling(self: Node) Node;
extern fn ts_node_parent(self: Node) Node;
extern fn ts_node_parse_state(self: Node) u16;
extern fn ts_node_prev_named_sibling(self: Node) Node;
extern fn ts_node_prev_sibling(self: Node) Node;
extern fn ts_node_start_byte(self: Node) u32;
extern fn ts_node_start_point(self: Node) Point;
extern fn ts_node_string(self: Node) [*c]u8;
extern fn ts_node_symbol(self: Node) u16;
extern fn ts_node_type(self: Node) [*:0]const u8;
extern fn ts_tree_cursor_new(node: Node) TreeCursor;
