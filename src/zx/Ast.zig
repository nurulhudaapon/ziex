pub fn fmt(allocator: std.mem.Allocator, source: [:0]const u8) !FmtResult {
    var aa = std.heap.ArenaAllocator.init(allocator);
    defer aa.deinit();
    const arena = aa.allocator();

    var parser_result = try Parser.parse(arena, source);
    defer parser_result.deinit(allocator);

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

const ParseOptions = struct {
    path: ?[]const u8 = null,
};

pub fn parse(gpa: std.mem.Allocator, zx_source: [:0]const u8, options: ParseOptions) !ParseResult {
    var aa = std.heap.ArenaAllocator.init(gpa);
    defer aa.deinit();
    const arena = aa.allocator();

    var parse_result = try Parser.parse(arena, zx_source);
    defer parse_result.deinit(arena);
    const render_result = try parse_result.renderAlloc(arena, .{ .mode = .zig, .sourcemap = false, .path = options.path });
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

    return ParseResult{
        .zig_ast = zig_ast,
        .zx_source = try gpa.dupeZ(u8, render_result.source),
        .zig_source = try gpa.dupeZ(u8, zig_sourcez),
        .client_components = components,
    };
}

pub const ParseResult = struct {
    zig_ast: std.zig.Ast,
    zx_source: [:0]const u8,
    zig_source: [:0]const u8,
    client_components: std.ArrayList(ClientComponentMetadata),

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
    }
};

pub const ClientComponentMetadata = Parser.ClientComponentMetadata;
const log = std.log.scoped(.ast);

const std = @import("std");
const Parser = @import("Parse.zig");
