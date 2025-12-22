test "tests:beforeAll" {
    gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_state.?.allocator();
    test_file_cache = try TestFileCache.init(gpa);
}

test "tests:afterAll" {
    if (test_file_cache) |*cache| {
        cache.deinit();
        test_file_cache = null;
    }
    if (gpa_state) |*gpa| {
        _ = gpa.deinit();
        gpa_state = null;
    }
}

// Control Flow
// === If ===
test "if" {
    try test_fmt("control_flow/if");
}
test "if_block" {
    try test_fmt("control_flow/if_block");
}
test "if_if_only" {
    // if (true) return error.Todo;
    try test_fmt("control_flow/if_if_only");
}
test "if_if_only_block" {
    // if (true) return error.Todo;
    try test_fmt("control_flow/if_if_only_block");
}
test "if_only" {
    try test_fmt("control_flow/if_only");
}
test "if_only_block" {
    try test_fmt("control_flow/if_only_block");
}
test "if_while" {
    // if (true) return error.Todo;
    try test_fmt("control_flow/if_while");
}
test "if_if" {
    try test_fmt("control_flow/if_if");
}
test "if_for" {
    try test_fmt("control_flow/if_for");
}
test "if_switch" {
    try test_fmt("control_flow/if_switch");
}

// === For ===
test "for" {
    try test_fmt("control_flow/for");
}
test "for_block" {
    try test_fmt("control_flow/for_block");
}
test "for_if" {
    if (true) return error.Todo;
    try test_fmt("control_flow/for_if");
}
test "for_for" {
    try test_fmt("control_flow/for_for");
}
test "for_switch" {
    try test_fmt("control_flow/for_switch");
}
test "for_while" {
    // if (true) return error.Todo;
    try test_fmt("control_flow/for_while");
}

// === Switch ===
test "switch" {
    try test_fmt("control_flow/switch");
}
test "switch_block" {
    // if (true) return error.Todo;
    try test_fmt("control_flow/switch_block");
}
test "switch_if" {
    try test_fmt("control_flow/switch_if");
}
test "switch_for" {
    if (true) return error.Todo;
    try test_fmt("control_flow/switch_for");
}
test "switch_switch" {
    if (true) return error.Todo;
    try test_fmt("control_flow/switch_switch");
}
test "switch_while" {
    if (true) return error.Todo;
    try test_fmt("control_flow/switch_while");
}

// === While ===
test "while" {
    try test_fmt("control_flow/while");
}
test "while_block" {
    try test_fmt("control_flow/while_block");
}
test "while_while" {
    // if (true) return error.Todo;
    try test_fmt("control_flow/while_while");
}
test "while_if" {
    // if (true) return error.Todo;
    try test_fmt("control_flow/while_if");
}
test "while_for" {
    // if (true) return error.Todo;
    try test_fmt("control_flow/while_for");
}
test "while_switch" {
    if (true) return error.Todo;
    try test_fmt("control_flow/while_switch");
}

// === Deeply Nested Control Flow (3-level) ===
test "if_for_if" {
    if (true) return error.Todo;
    try test_fmt("control_flow/if_for_if");
}

// === Miscellaneous ===
test "expression_text" {
    try test_fmt("expression/text");
}
test "expression_format" {
    try test_fmt("expression/format");
}
test "expression_component" {
    try test_fmt("expression/component");
}
test "expression_mixed" {
    if (true) return error.Todo;
    try test_fmt("expression/mixed");
}
test "expression_optional" {
    if (true) return error.Todo;
    try test_fmt("expression/optional");
}
test "expression_struct_access" {
    if (true) return error.Todo;
    try test_fmt("expression/struct_access");
}
test "expression_function_call" {
    if (true) return error.Todo;
    try test_fmt("expression/function_call");
}

test "component_basic" {
    try test_fmt("component/basic");
}
test "component_multiple" {
    try test_fmt("component/multiple");
}
test "component_csr_react" {
    try test_fmt("component/csr_react");
}
test "component_csr_react_multiple" {
    try test_fmt("component/csr_react_multiple");
}
test "component_nested" {
    if (true) return error.Todo;
    try test_fmt("component/nested");
}
test "component_children_only" {
    if (true) return error.Todo;
    try test_fmt("component/children_only");
}
test "component_csr_zig" {
    if (true) return error.Todo;
    try test_fmt("component/csr_zig");
}
test "component_import" {
    if (true) return error.Todo;
    try test_fmt("component/import");
}
test "component_root_cmp" {
    if (true) return error.Todo;
    try test_fmt("component/root_cmp");
}

// === Attribute ===
test "attribute_builtin" {
    if (true) return error.Todo;
    try test_fmt("attribute/builtin");
}
test "attribute_component" {
    if (true) return error.Todo;
    try test_fmt("attribute/component");
}
test "attribute_builtin_escaping" {
    if (true) return error.Todo;
    try test_fmt("attribute/builtin_escaping");
}
test "attribute_dynamic" {
    if (true) return error.Todo;
    try test_fmt("attribute/dynamic");
}

// === Element ===
test "element_void" {
    if (true) return error.Todo;
    try test_fmt("element/void");
}
test "element_empty" {
    if (true) return error.Todo;
    try test_fmt("element/empty");
}
test "element_nested" {
    if (true) return error.Todo;
    try test_fmt("element/nested");
}
test "element_fragment" {
    if (true) return error.Todo;
    try test_fmt("element/fragment");
}
test "element_fragment_root" {
    if (true) return error.Todo;
    try test_fmt("element/fragment_root");
}

// === Escaping ===
test "escaping_pre" {
    if (true) return error.Todo;
    try test_fmt("escaping/pre");
}
test "escaping_quotes" {
    if (true) return error.Todo;
    try test_fmt("escaping/quotes");
}

test "performance > fmt" {
    // if (true) return error.Todo;
    const MAX_TIME_MS = 50.0 * 8; // 50ms is on M1 Pro
    const MAX_TIME_PER_FILE_MS = 8.0 * 10; // 5ms is on M1 Pro

    var total_time_ns: f64 = 0.0;
    inline for (TestFileCache.test_files) |comptime_path| {
        const start_time = std.time.nanoTimestamp();
        try test_fmt_inner(comptime_path, true);
        const end_time = std.time.nanoTimestamp();
        const duration = @as(f64, @floatFromInt(end_time - start_time));
        total_time_ns += duration;
        const duration_ms = duration / std.time.ns_per_ms;
        try expectLessThan(MAX_TIME_PER_FILE_MS, duration_ms);
    }

    const total_time_ms = total_time_ns / std.time.ns_per_ms;
    const average_time_ms = total_time_ms / TestFileCache.test_files.len;
    std.debug.print("\x1b[33m⏲\x1b[0m fmt \x1b[90m>\x1b[0m {d:.2}ms | Avg: {d:.2}ms\n", .{ total_time_ms, average_time_ms });

    try expectLessThan(MAX_TIME_MS, total_time_ms);
    try expectLessThan(MAX_TIME_PER_FILE_MS, average_time_ms);
}

fn test_fmt(comptime file_path: []const u8) !void {
    try test_fmt_inner(file_path, false);
}

fn test_fmt_inner(comptime file_path: []const u8, comptime no_expect: bool) !void {
    const allocator = std.testing.allocator;
    const cache = test_file_cache orelse return error.CacheNotInitialized;

    // Construct paths for .zx and .zig files
    const source_path = file_path ++ ".zx";
    const expected_source_path = file_path ++ ".zx";

    // Get pre-loaded source file
    const source = cache.get(source_path) orelse return error.FileNotFound;
    const source_z = try allocator.dupeZ(u8, source);
    defer allocator.free(source_z);

    // Parse and transpile
    var result = try zx.Ast.fmt(allocator, source_z);
    defer result.deinit(allocator);

    // Get pre-loaded expected file
    const expected_source = cache.get(expected_source_path) orelse {
        std.log.err("Expected file not found: {s}\n", .{expected_source_path});
        return error.FileNotFound;
    };
    const expected_source_z = try allocator.dupeZ(u8, expected_source);
    defer allocator.free(expected_source_z);

    if (!no_expect) {
        try testing.expectEqualStrings(expected_source_z, result.source);
    }
}

fn expectLessThan(expected: f64, actual: f64) !void {
    if (actual > expected) {
        std.debug.print("\x1b[31m✗\x1b[0m Expected < {d:.2}ms, got {d:.2}ms\n", .{ expected, actual });
        return error.TestExpectedLessThan;
    }
}

var test_file_cache: ?TestFileCache = null;
var gpa_state: ?std.heap.GeneralPurposeAllocator(.{}) = null;

const TestFileCache = @import("./../test_util.zig").TestFileCache;

const std = @import("std");
const testing = std.testing;
const zx = @import("zx");
