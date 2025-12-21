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
    path: ?[]const u8,
};

pub fn parse(gpa: std.mem.Allocator, zx_source: [:0]const u8, options: ParseOptions) !ParseResult {
    var aa = std.heap.ArenaAllocator.init(gpa);
    defer aa.deinit();

    const arena = aa.allocator();
    const allocator = aa.allocator();

    // Legacy Prototyped Transpiler
    const legacy_parse_result = try Transpiler.transpile(arena, zx_source);
    const legacy_zig_source = try commentOutJsImports(arena, legacy_parse_result.zig_source);
    defer arena.free(legacy_zig_source);
    var legacy_zig_ast = try std.zig.Ast.parse(gpa, legacy_zig_source, .zig);
    const legacy_zig_sourcez = try allocator.dupeZ(u8, if (legacy_zig_ast.errors.len == 0) try legacy_zig_ast.renderAlloc(allocator) else legacy_zig_source);

    // New Tree-Sitter Based Transpiler
    var parse_result = try Parser.parse(arena, zx_source);
    defer parse_result.deinit(allocator);
    const render_result = try parse_result.renderAlloc(arena, .{ .mode = .zig, .sourcemap = false, .path = options.path });
    var zig_ast = try std.zig.Ast.parse(gpa, try allocator.dupeZ(u8, render_result.source), .zig);
    defer zig_ast.deinit(gpa);
    const zig_sourcez = try allocator.dupeZ(u8, if (zig_ast.errors.len == 0) try zig_ast.renderAlloc(allocator) else render_result.source);

    // if (ast.errors.len > 0) {
    //     for (ast.errors) |err| {
    //         var w: std.io.Writer.Allocating = .init(allocator);
    //         defer w.deinit();
    //         try ast.renderError(err, &w.writer);
    //         std.debug.print("{s}\n", .{w.written()});
    //     }
    //     ast.deinit(gpa);
    //     std.debug.print("Processed Zig Source: \n{s}\n", .{processed_zig_source});
    //     return error.ParseError;
    // }

    // var aw = std.io.Writer.Allocating.init(allocator);
    // defer aw.deinit();
    // std.zon.stringify.serialize(render_result.client_components, .{
    //     .whitespace = true,
    //     .emit_default_optional_fields = false,
    //     .emit_codepoint_literals = .always,
    // }, &aw.writer) catch @panic("OOM");
    // std.debug.print("ClientComponents: \n{s}\n", .{aw.written()});

    const legacy_components = try legacy_parse_result.client_components.clone(gpa);
    for (legacy_components.items) |*component| {
        component.name = try gpa.dupe(u8, component.name);
        component.path = try gpa.dupe(u8, component.path);
        component.id = try gpa.dupe(u8, component.id);
    }

    var new_components = std.ArrayList(Transpiler.ClientComponentMetadata).empty;
    try new_components.ensureTotalCapacity(gpa, render_result.client_components.len);

    for (render_result.client_components) |component| {
        try new_components.append(allocator, .{
            .name = try gpa.dupe(u8, component.name),
            .path = try gpa.dupe(u8, component.path),
            .id = try gpa.dupe(u8, component.id),
            .type = component.type,
        });
    }

    return ParseResult{
        .zig_ast = legacy_zig_ast,
        .zx_source = try gpa.dupeZ(u8, legacy_parse_result.zig_source),
        .zig_source = try gpa.dupeZ(u8, legacy_zig_sourcez),
        .new_zig_source = try gpa.dupeZ(u8, zig_sourcez),
        .client_components = legacy_components,
        .new_client_components = new_components,
    };
}

pub const ParseResult = struct {
    zig_ast: std.zig.Ast,
    zx_source: [:0]const u8,
    zig_source: [:0]const u8,
    new_zig_source: [:0]const u8,
    client_components: std.ArrayList(Transpiler.ClientComponentMetadata),
    new_client_components: std.ArrayList(Transpiler.ClientComponentMetadata),

    pub fn deinit(self: *ParseResult, allocator: std.mem.Allocator) void {
        self.zig_ast.deinit(allocator);
        allocator.free(self.zx_source);
        allocator.free(self.zig_source);
        allocator.free(self.new_zig_source);
        for (self.client_components.items) |*component| {
            allocator.free(component.name);
            allocator.free(component.path);
            allocator.free(component.id);
        }
        self.client_components.deinit(allocator);

        for (self.new_client_components.items) |*component| {
            allocator.free(component.name);
            allocator.free(component.path);
            allocator.free(component.id);
        }
        self.new_client_components.deinit(allocator);
    }
};

pub const ClientComponentMetadata = Transpiler.ClientComponentMetadata;

/// Post-process Zig source to comment out @jsImport declarations
fn commentOutJsImports(allocator: std.mem.Allocator, source: [:0]const u8) ![:0]const u8 {
    var result = std.ArrayList(u8){};
    try result.ensureTotalCapacity(allocator, source.len + 100); // Extra space for comment markers
    errdefer result.deinit(allocator);
    defer result.deinit(allocator);

    var lines = std.mem.splitScalar(u8, source, '\n');
    var first_line = true;

    while (lines.next()) |line| {
        if (!first_line) {
            try result.append(allocator, '\n');
        }
        first_line = false;

        // Check if line contains @jsImport
        if (std.mem.indexOf(u8, line, "@jsImport") != null) {
            // Comment out the line
            try result.appendSlice(allocator, "// ");
            try result.appendSlice(allocator, line);
        } else {
            // Keep the line as-is
            try result.appendSlice(allocator, line);
        }
    }

    return try allocator.dupeZ(u8, result.items);
}

const log = std.log.scoped(.ast);

const std = @import("std");
const Transpiler = @import("Transpiler_prototype.zig");
const Parser = @import("Parse.zig");
