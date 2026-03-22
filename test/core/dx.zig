const std = @import("std");
const testing = std.testing;
const zx = @import("zx");
const sourcemap = zx.sourcemap;

test "sm > VLQ encode/decode roundtrip" {
    const allocator = testing.allocator;

    // Build a sourcemap with known mappings
    var builder = sourcemap.Builder.init(allocator);
    defer builder.deinit();

    const mappings = [_]sourcemap.Mapping{
        .{ .generated_line = 0, .generated_column = 0, .source_line = 0, .source_column = 0 },
        .{ .generated_line = 0, .generated_column = 10, .source_line = 0, .source_column = 5 },
        .{ .generated_line = 1, .generated_column = 4, .source_line = 1, .source_column = 4 },
        .{ .generated_line = 2, .generated_column = 8, .source_line = 3, .source_column = 12 },
        .{ .generated_line = 5, .generated_column = 0, .source_line = 10, .source_column = 0 },
    };

    for (&mappings) |m| {
        try builder.addMapping(m);
    }

    var sm = try builder.build();
    defer sm.deinit(@constCast(&allocator).*);

    // Decode and verify roundtrip
    var decoded = try sm.decode(allocator);
    defer decoded.deinit();

    try testing.expectEqual(mappings.len, decoded.entries.len);

    for (&mappings, decoded.entries) |expected, actual| {
        try testing.expectEqual(expected.generated_line, actual.generated_line);
        try testing.expectEqual(expected.generated_column, actual.generated_column);
        try testing.expectEqual(expected.source_line, actual.source_line);
        try testing.expectEqual(expected.source_column, actual.source_column);
    }
}

test "sm > sourceToGenerated exact match" {
    const allocator = testing.allocator;

    var builder = sourcemap.Builder.init(allocator);
    defer builder.deinit();

    // Simulate: source line 2, col 4 maps to generated line 5, col 8
    try builder.addMapping(.{ .generated_line = 5, .generated_column = 8, .source_line = 2, .source_column = 4 });
    // source line 2, col 10 maps to generated line 5, col 20
    try builder.addMapping(.{ .generated_line = 5, .generated_column = 20, .source_line = 2, .source_column = 10 });

    var sm = try builder.build();
    defer sm.deinit(@constCast(&allocator).*);

    var decoded = try sm.decode(allocator);
    defer decoded.deinit();

    // Exact match
    const result = decoded.sourceToGenerated(2, 4).?;
    try testing.expectEqual(@as(i32, 5), result.generated_line);
    try testing.expectEqual(@as(i32, 8), result.generated_column);

    // Position between two mappings on same source line — should use closest before
    const between = decoded.sourceToGenerated(2, 7).?;
    try testing.expectEqual(@as(i32, 5), between.generated_line);
    // col 7 is 3 past the mapping at col 4, so generated col = 8 + 3 = 11
    try testing.expectEqual(@as(i32, 11), between.generated_column);
}

test "sm > generatedToSource exact match" {
    const allocator = testing.allocator;

    var builder = sourcemap.Builder.init(allocator);
    defer builder.deinit();

    try builder.addMapping(.{ .generated_line = 3, .generated_column = 0, .source_line = 1, .source_column = 0 });
    try builder.addMapping(.{ .generated_line = 3, .generated_column = 15, .source_line = 1, .source_column = 8 });

    var sm = try builder.build();
    defer sm.deinit(@constCast(&allocator).*);

    var decoded = try sm.decode(allocator);
    defer decoded.deinit();

    // Exact match
    const result = decoded.generatedToSource(3, 0).?;
    try testing.expectEqual(@as(i32, 1), result.source_line);
    try testing.expectEqual(@as(i32, 0), result.source_column);

    // Position between mappings
    const between = decoded.generatedToSource(3, 5).?;
    try testing.expectEqual(@as(i32, 1), between.source_line);
    try testing.expectEqual(@as(i32, 5), between.source_column);
}

test "sm > lookup returns null for unmapped position" {
    const allocator = testing.allocator;

    var builder = sourcemap.Builder.init(allocator);
    defer builder.deinit();

    try builder.addMapping(.{ .generated_line = 5, .generated_column = 0, .source_line = 3, .source_column = 0 });

    var sm = try builder.build();
    defer sm.deinit(@constCast(&allocator).*);

    var decoded = try sm.decode(allocator);
    defer decoded.deinit();

    // Line before any mapping — should return null
    const result = decoded.sourceToGenerated(0, 0);
    try testing.expectEqual(@as(?sourcemap.Mapping, null), result);
}

test "sm > e2e simple element transpilation" {
    const allocator = testing.allocator;

    const source =
        \\pub fn Page(allocator: zx.Allocator) zx.Component {
        \\    return (
        \\        <div>Hello</div>
        \\    );
        \\}
        \\
        \\const zx = @import("zx");
    ;
    const source_z = try allocator.dupeZ(u8, source);
    defer allocator.free(source_z);

    var result = try zx.Ast.parse(allocator, source_z, .{ .map = .inlined });
    defer result.deinit(allocator);

    // Sourcemap should be present
    try testing.expect(result.sourcemap != null);

    const sm = result.sourcemap.?;
    var decoded = try sm.decode(allocator);
    defer decoded.deinit();

    // Should have mappings
    try testing.expect(decoded.entries.len > 0);
    const raw_zig = result.zx_source;

    // "pub" at source line 0, col 0 should map to generated line 0, col 0
    const pub_mapping = decoded.sourceToGenerated(0, 0).?;
    try testing.expectEqual(@as(i32, 0), pub_mapping.generated_line);
    try testing.expectEqual(@as(i32, 0), pub_mapping.generated_column);

    // Verify the generated position actually contains "pub"
    const gen_offset = lineColToOffset(raw_zig, pub_mapping.generated_line, pub_mapping.generated_column);
    try testing.expect(gen_offset != null);
    if (gen_offset) |off| {
        try testing.expect(std.mem.startsWith(u8, raw_zig[off..], "pub"));
    }

    // "const zx" at source line 6, col 0 should map to a generated position containing "const zx"
    const const_mapping = decoded.sourceToGenerated(6, 0).?;
    const const_offset = lineColToOffset(raw_zig, const_mapping.generated_line, const_mapping.generated_column);
    try testing.expect(const_offset != null);
    if (const_offset) |off| {
        try testing.expect(std.mem.startsWith(u8, raw_zig[off..], "const"));
    }
}

test "sm > e2e generatedToSource roundtrip for zig code" {
    const allocator = testing.allocator;

    const source =
        \\const std = @import("std");
        \\
        \\pub fn hello() void {
        \\    std.debug.print("hello\n", .{});
        \\}
    ;
    const source_z = try allocator.dupeZ(u8, source);
    defer allocator.free(source_z);

    var result = try zx.Ast.parse(allocator, source_z, .{ .map = .inlined });
    defer result.deinit(allocator);

    try testing.expect(result.sourcemap != null);

    const sm = result.sourcemap.?;
    var decoded = try sm.decode(allocator);
    defer decoded.deinit();

    // Pure zig code should map 1:1 (source == generated for passthrough code)
    // "const" at line 0, col 0
    const m = decoded.sourceToGenerated(0, 0).?;
    try testing.expectEqual(@as(i32, 0), m.generated_line);
    try testing.expectEqual(@as(i32, 0), m.generated_column);

    // Reverse lookup should also work
    const rev = decoded.generatedToSource(m.generated_line, m.generated_column).?;
    try testing.expectEqual(@as(i32, 0), rev.source_line);
    try testing.expectEqual(@as(i32, 0), rev.source_column);
}

test "sm > e2e expression in element" {
    const allocator = testing.allocator;

    const source =
        \\pub fn Page(allocator: zx.Allocator) zx.Component {
        \\    const name = "world";
        \\    return (
        \\        <p>Hello {name}</p>
        \\    );
        \\}
        \\
        \\const zx = @import("zx");
    ;
    const source_z = try allocator.dupeZ(u8, source);
    defer allocator.free(source_z);

    var result = try zx.Ast.parse(allocator, source_z, .{ .map = .inlined });
    defer result.deinit(allocator);

    try testing.expect(result.sourcemap != null);

    const sm = result.sourcemap.?;
    var decoded = try sm.decode(allocator);
    defer decoded.deinit();

    const raw_zig = result.zx_source;

    // "const name" at source line 1, col 4 should map to a valid generated position
    const name_mapping = decoded.sourceToGenerated(1, 4).?;
    const name_offset = lineColToOffset(raw_zig, name_mapping.generated_line, name_mapping.generated_column);
    try testing.expect(name_offset != null);
    if (name_offset) |off| {
        try testing.expect(std.mem.startsWith(u8, raw_zig[off..], "const"));
    }

    // The expression {name} at source line 3 should map somewhere in generated that contains "name"
    // Find "name" in the source — it's at line 3, the expression is after "Hello "
    // In .zx, line 3 is: "        <p>Hello {name}</p>"
    // "name" starts at col 16 (after 8 spaces + "<p>Hello {")
    const expr_mapping = decoded.sourceToGenerated(3, 17).?;
    const expr_offset = lineColToOffset(raw_zig, expr_mapping.generated_line, expr_mapping.generated_column);
    try testing.expect(expr_offset != null);
}

test "sm > all test files produce valid sourcemaps" {
    const allocator = testing.allocator;
    const test_files = [_][]const u8{
        "test/data/element/nested.zx",
        "test/data/expression/text.zx",
        "test/data/control_flow/if.zx",
        "test/data/control_flow/for.zx",
        "test/data/component/basic.zx",
        "test/data/attribute/dynamic.zx",
    };

    for (test_files) |path| {
        const source = std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize)) catch continue;
        defer allocator.free(source);

        const source_z = try allocator.dupeZ(u8, source);
        defer allocator.free(source_z);

        var result = zx.Ast.parse(allocator, source_z, .{ .map = .inlined, .path = path }) catch continue;
        defer result.deinit(allocator);

        // Sourcemap must be present
        if (result.sourcemap) |sm| {
            // Must decode without error
            var decoded = try sm.decode(allocator);
            defer decoded.deinit();

            // Should have at least some mappings
            try testing.expect(decoded.entries.len > 0);

            // All generated positions should be within the raw zig source bounds
            const raw_zig = result.zx_source;
            for (decoded.entries) |entry| {
                const offset = lineColToOffset(raw_zig, entry.generated_line, entry.generated_column);
                if (offset == null) {
                    std.debug.print("FAIL: {s}: mapping gen {d}:{d} is out of bounds (raw_zig len={d})\n", .{
                        path,
                        entry.generated_line,
                        entry.generated_column,
                        raw_zig.len,
                    });
                    return error.MappingOutOfBounds;
                }
            }
        } else {
            std.debug.print("FAIL: {s}: no sourcemap generated\n", .{path});
            return error.NoSourceMap;
        }
    }
}

test "sm > generate sourcemap debug files" {
    if (!shouldGenerateDebugFiles()) return;

    const allocator = testing.allocator;

    const test_files = [_]struct { zx_path: []const u8, name: []const u8 }{
        .{ .zx_path = "test/data/element/nested.zx", .name = "nested" },
        .{ .zx_path = "test/data/expression/text.zx", .name = "text" },
        .{ .zx_path = "test/data/control_flow/if.zx", .name = "if" },
        .{ .zx_path = "test/data/control_flow/for.zx", .name = "for" },
        .{ .zx_path = "test/data/component/basic.zx", .name = "basic" },
        .{ .zx_path = "test/data/attribute/dynamic.zx", .name = "dynamic" },
    };

    // Ensure output directory exists
    std.fs.cwd().makePath(".zig-cache/tmp/.zx/sourcemap-debug") catch {};

    for (test_files) |tf| {
        const source = std.fs.cwd().readFileAlloc(allocator, tf.zx_path, std.math.maxInt(usize)) catch continue;
        defer allocator.free(source);

        const source_z = try allocator.dupeZ(u8, source);
        defer allocator.free(source_z);

        var result = zx.Ast.parse(allocator, source_z, .{ .map = .inlined, .path = tf.zx_path }) catch continue;
        defer result.deinit(allocator);

        const sm = result.sourcemap orelse continue;

        // Generate the sourcemap JSON
        const gen_file = try std.fmt.allocPrint(allocator, "{s}.zig", .{tf.name});
        defer allocator.free(gen_file);
        const src_file = try std.fmt.allocPrint(allocator, "{s}.zx", .{tf.name});
        defer allocator.free(src_file);
        const map_json = try sm.toJSON(allocator, gen_file, src_file, source, result.zx_source);
        defer allocator.free(map_json);

        // Write the .map JSON file
        const map_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/.zx/sourcemap-debug/{s}.zig.map", .{tf.name});
        defer allocator.free(map_path);
        try writeFile(map_path, map_json);

        // Write the raw transpiled .zig with inline sourcemap comment
        // Format: //# sourceMappingURL=data:application/json;base64,<base64-encoded-json>
        const b64_len = std.base64.standard.Encoder.calcSize(map_json.len);
        const b64_buf = try allocator.alloc(u8, b64_len);
        defer allocator.free(b64_buf);
        _ = std.base64.standard.Encoder.encode(b64_buf, map_json);

        const inline_zig = try std.fmt.allocPrint(
            allocator,
            "{s}\n//# sourceMappingURL=data:application/json;base64,{s}\n",
            .{ result.zx_source, b64_buf },
        );
        defer allocator.free(inline_zig);

        const zig_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/.zx/sourcemap-debug/{s}.zig", .{tf.name});
        defer allocator.free(zig_path);
        try writeFile(zig_path, inline_zig);

        // Also write the original .zx source for reference
        const zx_out_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/.zx/sourcemap-debug/{s}.zx", .{tf.name});
        defer allocator.free(zx_out_path);
        try writeFile(zx_out_path, source);

        std.debug.print("  wrote: {s} + .map + .zx\n", .{zig_path});
    }

    std.debug.print("\nSourcemap debug files written to .zig-cache/tmp/.zx/sourcemap-debug/\n", .{});
    std.debug.print("Visualize at: https://evanw.github.io/source-map-visualization/\n", .{});
    std.debug.print("  - Paste the .zig content as 'generated'\n", .{});
    std.debug.print("  - Paste the .map content as 'source map'\n", .{});
}

fn shouldGenerateDebugFiles() bool {
    const val = std.process.getEnvVarOwned(testing.allocator, "SM_DEBUG") catch return false;
    testing.allocator.free(val);
    return true;
}

fn writeFile(path: []const u8, content: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(content);
}

fn lineColToOffset(source: []const u8, line: i32, col: i32) ?usize {
    var current_line: i32 = 0;
    var i: usize = 0;

    while (current_line < line and i < source.len) {
        if (source[i] == '\n') current_line += 1;
        i += 1;
    }
    if (current_line != line) return null;

    const offset = i + @as(usize, @intCast(col));
    if (offset > source.len) return null;
    return offset;
}
