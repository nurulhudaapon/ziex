pub fn fmt(allocator: std.mem.Allocator, source: [:0]const u8) !FmtResult {
    var aa = std.heap.ArenaAllocator.init(allocator);
    defer aa.deinit();
    const arena = aa.allocator();

    var parser_result = try Parser.parse(arena, source, .zx);
    defer parser_result.deinit(allocator);

    // Don't format if tree has syntax errors
    if (parser_result.tree.rootNode().hasError()) {
        return error.TreeHasErrors;
    }

    const render_result = try parser_result.renderAlloc(arena, .{ .mode = .zx, .sourcemap = false, .path = null });
    const formatted_sourcez = try allocator.dupeZ(u8, render_result.source);

    return .{
        .source = formatted_sourcez,
    };
}

pub const FmtResult = struct {
    source: [:0]const u8,

    pub fn deinit(self: *FmtResult, allocator: std.mem.Allocator) void {
        allocator.free(self.source);
    }
};

pub const ParseOptions = struct {
    pub const MapMode = union(enum) {
        none,
        file: []const u8,
        inlined,

        pub fn enabled(self: MapMode) bool {
            return switch (self) {
                .none => false,
                .file => true,
                .inlined => true,
            };
        }
    };

    path: ?[]const u8 = null,
    map: MapMode = .none,
    lang: Parser.Language = .zx,
};

pub fn parse(gpa: std.mem.Allocator, zx_source: [:0]const u8, options: ParseOptions) !ParseResult {
    var aa = std.heap.ArenaAllocator.init(gpa);
    defer aa.deinit();
    const arena = aa.allocator();

    var parse_result = try Parser.parse(arena, zx_source, options.lang);
    defer parse_result.deinit(arena);
    const render_result = try parse_result.renderAlloc(arena, .{ .mode = .zig, .sourcemap = options.map.enabled(), .path = options.path });
    var zig_ast = try std.zig.Ast.parse(gpa, try arena.dupeZ(u8, render_result.source), .zig);
    const zig_sourcez = try arena.dupeZ(u8, if (zig_ast.errors.len == 0) try zig_ast.renderAlloc(arena) else render_result.source);

    var components = std.ArrayList(ClientComponentMetadata).empty;
    try components.ensureTotalCapacity(gpa, render_result.client_components.len);

    for (render_result.client_components) |component| {
        try components.append(gpa, .{
            .name = try gpa.dupe(u8, component.name),
            .path = try gpa.dupe(u8, component.path),
            .id = try gpa.dupe(u8, component.id),
            .type = component.type,
        });
    }

    // Copy sourcemap if present
    const result_sourcemap: ?sourcemap.SourceMap = if (render_result.sourcemap) |sm|
        .{ .mappings = try gpa.dupe(u8, sm.mappings) }
    else
        null;

    return ParseResult{
        .zig_ast = zig_ast,
        .zx_source = try gpa.dupeZ(u8, render_result.source),
        .zig_source = try gpa.dupeZ(u8, zig_sourcez),
        .client_components = components,
        .sourcemap = result_sourcemap,
    };
}

pub const ParseResult = struct {
    zig_ast: std.zig.Ast,
    zx_source: [:0]const u8,
    zig_source: [:0]const u8,
    client_components: std.ArrayList(ClientComponentMetadata),
    sourcemap: ?sourcemap.SourceMap = null,

    pub fn deinit(self: *ParseResult, allocator: std.mem.Allocator) void {
        self.zig_ast.deinit(allocator);
        allocator.free(self.zx_source);
        allocator.free(self.zig_source);
        for (self.client_components.items) |*component| {
            allocator.free(component.name);
            allocator.free(component.path);
            allocator.free(component.id);
        }
        self.client_components.deinit(allocator);
        if (self.sourcemap) |*sm| {
            sm.deinit(allocator);
        }
    }
};

pub const ClientComponentMetadata = Parser.ClientComponentMetadata;
pub const SourceMap = sourcemap.SourceMap;
const log = std.log.scoped(.ast);

const std = @import("std");
const Parser = @import("Parse.zig");
const sourcemap = @import("sourcemap.zig");
