const std = @import("std");
const ts = @import("tree_sitter");
const Parse = @import("Parse.zig");

/// Severity level of a diagnostic message.
pub const Severity = enum { err, warning };

/// A single structured diagnostic produced during validation.
pub const Diagnostic = struct {
    /// Human-readable description of the problem.
    message: []const u8,
    /// 0-based start line number in the source file.
    start_line: u32,
    /// 0-based start column number in the source file.
    start_column: u32,
    /// 0-based end line number in the source file.
    end_line: u32,
    /// 0-based end column number in the source file.
    end_column: u32,
    /// Severity of this diagnostic.
    severity: Severity,
};

/// An owned, heap-allocated list of `Diagnostic` values.
/// Always call `deinit()` when done.
pub const DiagnosticList = struct {
    items: []const Diagnostic,
    allocator: std.mem.Allocator,

    /// Returns `true` if any diagnostic has `.err` severity.
    pub fn hasErrors(self: DiagnosticList) bool {
        for (self.items) |d| {
            if (d.severity == .err) return true;
        }
        return false;
    }

    /// Free all memory owned by this list (messages and the slice itself).
    pub fn deinit(self: *DiagnosticList) void {
        for (self.items) |d| self.allocator.free(d.message);
        self.allocator.free(self.items);
    }
};

/// Walk `parser`'s tree-sitter AST and collect all syntax errors as diagnostics.
///
/// ERROR nodes produce "Unexpected token '<text>'" messages.
/// MISSING nodes produce "Expected '<token>'" messages.
///
/// The caller owns the returned `DiagnosticList` and must call `deinit()` on it.
pub fn validate(allocator: std.mem.Allocator, parser: *Parse) !DiagnosticList {
    var list = std.ArrayList(Diagnostic).empty;
    errdefer {
        for (list.items) |d| allocator.free(d.message);
        list.deinit(allocator);
    }

    const root = parser.tree.rootNode();
    if (root.hasError()) {
        try collectDiagnostics(allocator, root, parser.source, &list);
    }

    return DiagnosticList{
        .items = try list.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Recursively walk `node` and append a `Diagnostic` for every ERROR or
/// MISSING descendant.  We skip recursing into ERROR nodes because the node
/// itself already represents the entire bad region.
fn collectDiagnostics(
    allocator: std.mem.Allocator,
    node: ts.Node,
    source: []const u8,
    list: *std.ArrayList(Diagnostic),
) !void {
    if (node.isError()) {
        try list.append(allocator, try errorDiagnostic(allocator, node, source));
        // Do not descend — the ERROR node already covers the invalid region.
        return;
    }

    if (node.isMissing()) {
        try list.append(allocator, try missingDiagnostic(allocator, node));
        return;
    }

    // Only recurse into subtrees that carry an error to avoid a full-tree walk
    // on otherwise valid source.
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        if (child.hasError() or child.isMissing()) {
            try collectDiagnostics(allocator, child, source, list);
        }
    }
}

fn errorDiagnostic(allocator: std.mem.Allocator, node: ts.Node, source: []const u8) !Diagnostic {
    const start_point = node.startPoint();
    const end_point = node.endPoint();
    const start = node.startByte();
    const end = node.endByte();

    // Extract the offending text for a more informative message, but cap its
    // length so the message stays readable.
    const max_snippet = 48;
    const raw = if (start < end and end <= source.len) source[start..end] else "";
    const snippet = if (raw.len > max_snippet) raw[0..max_snippet] else raw;

    const message = if (snippet.len > 0)
        try std.fmt.allocPrint(allocator, "Unexpected token '{s}'", .{snippet})
    else
        try allocator.dupe(u8, "Syntax error");

    return Diagnostic{
        .message = message,
        .start_line = start_point.row,
        .start_column = start_point.column,
        .end_line = end_point.row,
        .end_column = end_point.column,
        .severity = .err,
    };
}

fn missingDiagnostic(allocator: std.mem.Allocator, node: ts.Node) !Diagnostic {
    const start_point = node.startPoint();
    const end_point = node.endPoint();
    const token = node.kind();
    const message = try std.fmt.allocPrint(allocator, "Expected '{s}'", .{token});

    return Diagnostic{
        .message = message,
        .start_line = start_point.row,
        .start_column = start_point.column,
        .end_line = end_point.row,
        .end_column = end_point.column,
        .severity = .err,
    };
}
