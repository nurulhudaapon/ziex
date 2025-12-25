const std = @import("std");

const Point = @import("point.zig").Point;
const Node = @import("node.zig").Node;
const Tree = @import("tree.zig").Tree;

/// A stateful object for walking a syntax tree efficiently.
pub const TreeCursor = extern struct {
    /// **Internal.** The syntax tree this cursor belongs to.
    tree: *const Tree,

    /// **Internal.** The id of the tree cursor.
    id: *const anyopaque,

    /// **Internal.** The context of the tree cursor.
    context: [3]u32,

    /// Delete the tree cursor, freeing all of the memory that it used.
    pub fn destroy(self: *TreeCursor) void {
        ts_tree_cursor_delete(self);
    }

    /// Create a deep copy of the tree cursor.
    pub fn dupe(self: *const TreeCursor) TreeCursor {
        return ts_tree_cursor_copy(self);
    }

    /// Get the current node of the tree cursor.
    pub fn node(self: *const TreeCursor) Node {
        return ts_tree_cursor_current_node(self);
    }

    /// Get the numerical field id of this tree cursor's current node.
    ///
    /// This returns `0` if the current node doesn't have a field.
    ///
    /// See also `TreeCursor.field_name`.
    pub fn fieldId(self: *const TreeCursor) u16 {
        return ts_tree_cursor_current_field_id(self);
    }

    /// Get the field name of the tree cursor's current node.
    ///
    /// This returns `null` if the current node doesn't have a field.
    pub fn fieldName(self: *const TreeCursor) ?[]const u8 {
        return if (ts_tree_cursor_current_field_name(self)) |name| std.mem.span(name) else null;
    }

    /// Get the depth of the cursor's current node relative to
    /// the original node that the cursor was constructed with.
    pub fn depth(self: *const TreeCursor) u32 {
        return ts_tree_cursor_current_depth(self);
    }

    /// Get the index of the cursor's current node out of all of the
    /// descendants of the original node that the cursor was constructed with.
    pub fn descendantIndex(self: *const TreeCursor) u32 {
        return ts_tree_cursor_current_descendant_index(self);
    }

    /// Move the cursor to the first child of its current node.
    ///
    /// This returns `true` if the cursor successfully moved,
    /// or `false` if there were no children.
    pub fn gotoFirstChild(self: *TreeCursor) bool {
        return ts_tree_cursor_goto_first_child(self);
    }

    /// Move the cursor to the last child of its current node.
    ///
    /// This returns `true` if the cursor successfully moved,
    /// or `false` if there were no children.
    pub fn gotoLastChild(self: *TreeCursor) bool {
        return ts_tree_cursor_goto_last_child(self);
    }

    /// Move the cursor to the parent of its current node.
    ///
    /// This returns `true` if the cursor successfully moved,
    /// or `false` if there was no parent node.
    pub fn gotoParent(self: *TreeCursor) bool {
        return ts_tree_cursor_goto_parent(self);
    }

    /// Move the cursor to the next sibling of its current node.
    ///
    /// This returns `true` if the cursor successfully moved,
    /// or `false` if there was no next sibling node.
    pub fn gotoNextSibling(self: *TreeCursor) bool {
        return ts_tree_cursor_goto_next_sibling(self);
    }

    /// Move this cursor to the previous sibling of its current node.
    ///
    /// This returns `true` if the cursor successfully moved,
    /// and returns `false` if there was no previous sibling node.
    ///
    /// Note, that this function may be slower than `TreeCursor.goto_next_sibling`
    /// due to how node positions are stored. In the worst case, this will
    /// need to iterate through all the children up to the previous sibling node
    /// to recalculate its position. Also note that the node the cursor was
    /// constructed with is considered the root of the cursor, and the cursor
    /// cannot walk outside this node.
    pub fn gotoPreviousSibling(self: *TreeCursor) bool {
        return ts_tree_cursor_goto_previous_sibling(self);
    }

    /// Move the cursor to the nth descendant node of the
    /// original node that the cursor was constructed with,
    /// where `0` represents the original node itself.
    pub fn gotoDescendant(self: *TreeCursor, index: u32) void {
        return ts_tree_cursor_goto_descendant(self, index);
    }

    /// Move the cursor to the first child of its current node
    /// that contains or starts after the given byte offset.
    ///
    /// This returns the index of the child node if one was found, or `null`.
    pub fn gotoFirstChildForByte(self: *TreeCursor, byte: u32) ?u32 {
        const index = ts_tree_cursor_goto_first_child_for_byte(self, byte);
        return if (index >= 0) @intCast(index) else null;
    }

    /// Move the cursor to the first child of its current node
    /// that contains or starts after the given point.
    ///
    /// This returns the index of the child node if one was found, or `null`.
    pub fn gotoFirstChildForPoint(self: *TreeCursor, point: Point) ?u32 {
        const index = ts_tree_cursor_goto_first_child_for_point(self, point);
        return if (index >= 0) @intCast(index) else null;
    }

    /// Re-initialize a tree cursor to start at the node it was constructed with.
    pub fn reset(self: *TreeCursor, target: Node) void {
        ts_tree_cursor_reset(self, target);
    }

    /// Re-initialize a tree cursor to the same position as another cursor.
    ///
    /// Unlike `TreeCursor.reset`, this will not lose parent
    /// information and allows reusing already created cursors.
    pub fn resetTo(self: *TreeCursor, other: *const TreeCursor) void {
        ts_tree_cursor_reset_to(self, other);
    }
};

extern fn ts_tree_cursor_delete(self: *TreeCursor) void;
extern fn ts_tree_cursor_reset(self: *TreeCursor, node: Node) void;
extern fn ts_tree_cursor_reset_to(dst: *TreeCursor, src: *const TreeCursor) void;
extern fn ts_tree_cursor_current_node(self: *const TreeCursor) Node;
extern fn ts_tree_cursor_current_field_name(self: *const TreeCursor) ?[*:0]const u8;
extern fn ts_tree_cursor_current_field_id(self: *const TreeCursor) u16;
extern fn ts_tree_cursor_goto_parent(self: *TreeCursor) bool;
extern fn ts_tree_cursor_goto_next_sibling(self: *TreeCursor) bool;
extern fn ts_tree_cursor_goto_previous_sibling(self: *TreeCursor) bool;
extern fn ts_tree_cursor_goto_first_child(self: *TreeCursor) bool;
extern fn ts_tree_cursor_goto_last_child(self: *TreeCursor) bool;
extern fn ts_tree_cursor_goto_descendant(self: *TreeCursor, goal_descendant_index: u32) void;
extern fn ts_tree_cursor_current_descendant_index(self: *const TreeCursor) u32;
extern fn ts_tree_cursor_current_depth(self: *const TreeCursor) u32;
extern fn ts_tree_cursor_goto_first_child_for_byte(self: *TreeCursor, goal_byte: u32) i64;
extern fn ts_tree_cursor_goto_first_child_for_point(self: *TreeCursor, goal_point: Point) i64;
extern fn ts_tree_cursor_copy(cursor: *const TreeCursor) TreeCursor;
