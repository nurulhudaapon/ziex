const std = @import("std");
const testing = std.testing;
const zx = @import("zx");

/// Test the props hydration parser (zx.hydration)
const parseProps = zx.hydration.parseProps;
const PropsParser = zx.hydration.PropsParser;

// ============================================================================
// Test Fixtures
// ============================================================================

const Status = enum { pending, active, completed };

const SimpleProps = struct { count: i32, enabled: bool };
const NumberProps = struct { int_val: i32, negative: i32, zero: i32, float_val: f32, negative_float: f32 };
const NestedInner = struct { value: i32, flag: bool };
const NestedProps = struct { outer_val: i32, inner: NestedInner, outer_flag: bool };
const OptionalProps = struct { required: i32, optional_int: ?i32, optional_str: ?[]const u8 };
const ArrayProps = struct { scores: [3]i32, flags: [2]bool };
const EnumProps = struct { status: Status, value: i32 };
const ComplexProps = struct {
    initial: i32,
    negative: i32,
    zero_val: i32,
    float_val: f32,
    negative_float: f32,
    shared: bool,
    disabled: bool,
    label: []const u8,
    escaped_str: []const u8,
    optional_int: ?i32,
    optional_str: ?[]const u8,
    nested: NestedInner,
    scores: [3]i32,
    status: Status,
};

// ============================================================================
// Integer Tests
// ============================================================================

test "int positive" {
    const P = struct { value: i32 };
    try testing.expectEqual(@as(i32, 42), parseProps(P, testing.allocator, "[42]").value);
}

test "int negative" {
    const P = struct { value: i32 };
    try testing.expectEqual(@as(i32, -100), parseProps(P, testing.allocator, "[-100]").value);
}

test "int zero" {
    const P = struct { value: i32 };
    try testing.expectEqual(@as(i32, 0), parseProps(P, testing.allocator, "[0]").value);
}

test "int max" {
    const P = struct { value: i32 };
    try testing.expectEqual(@as(i32, 2147483647), parseProps(P, testing.allocator, "[2147483647]").value);
}

test "int min" {
    const P = struct { value: i32 };
    try testing.expectEqual(@as(i32, -2147483648), parseProps(P, testing.allocator, "[-2147483648]").value);
}

test "int multiple" {
    const r = parseProps(NumberProps, testing.allocator, "[42,-100,0,0,0]");
    try testing.expectEqual(@as(i32, 42), r.int_val);
    try testing.expectEqual(@as(i32, -100), r.negative);
    try testing.expectEqual(@as(i32, 0), r.zero);
}

// ============================================================================
// Float Tests
// ============================================================================

test "float positive" {
    const P = struct { value: f32 };
    try testing.expectApproxEqAbs(@as(f32, 3.14), parseProps(P, testing.allocator, "[3.14]").value, 0.001);
}

test "float negative" {
    const P = struct { value: f32 };
    try testing.expectApproxEqAbs(@as(f32, -2.5), parseProps(P, testing.allocator, "[-2.5]").value, 0.001);
}

test "float zero" {
    const P = struct { value: f32 };
    try testing.expectApproxEqAbs(@as(f32, 0.0), parseProps(P, testing.allocator, "[0.0]").value, 0.001);
}

test "float small" {
    const P = struct { value: f32 };
    try testing.expectApproxEqAbs(@as(f32, 0.000001), parseProps(P, testing.allocator, "[0.000001]").value, 0.0000001);
}

test "float scientific" {
    const P = struct { value: f32 };
    try testing.expectApproxEqAbs(@as(f32, 1500.0), parseProps(P, testing.allocator, "[1.5e3]").value, 0.1);
}

// ============================================================================
// Boolean Tests
// ============================================================================

test "bool true" {
    const P = struct { value: bool };
    try testing.expect(parseProps(P, testing.allocator, "[true]").value);
}

test "bool false" {
    const P = struct { value: bool };
    try testing.expect(!parseProps(P, testing.allocator, "[false]").value);
}

test "bool multiple" {
    const P = struct { a: bool, b: bool, c: bool };
    const r = parseProps(P, testing.allocator, "[true,false,true]");
    try testing.expect(r.a and !r.b and r.c);
}

// ============================================================================
// String Tests
// ============================================================================

test "string simple" {
    const P = struct { value: []const u8 };
    const r = parseProps(P, testing.allocator, "[\"hello\"]");
    defer testing.allocator.free(r.value);
    try testing.expectEqualStrings("hello", r.value);
}

test "string empty" {
    const P = struct { value: []const u8 };
    const r = parseProps(P, testing.allocator, "[\"\"]");
    defer testing.allocator.free(r.value);
    try testing.expectEqualStrings("", r.value);
}

test "string spaces" {
    const P = struct { value: []const u8 };
    const r = parseProps(P, testing.allocator, "[\"hello world\"]");
    defer testing.allocator.free(r.value);
    try testing.expectEqualStrings("hello world", r.value);
}

test "string escape newline" {
    const P = struct { value: []const u8 };
    const r = parseProps(P, testing.allocator, "[\"line1\\nline2\"]");
    defer testing.allocator.free(r.value);
    try testing.expectEqualStrings("line1\nline2", r.value);
}

test "string escape tab" {
    const P = struct { value: []const u8 };
    const r = parseProps(P, testing.allocator, "[\"col1\\tcol2\"]");
    defer testing.allocator.free(r.value);
    try testing.expectEqualStrings("col1\tcol2", r.value);
}

test "string escape quote" {
    const P = struct { value: []const u8 };
    const r = parseProps(P, testing.allocator, "[\"say \\\"hello\\\"\"]");
    defer testing.allocator.free(r.value);
    try testing.expectEqualStrings("say \"hello\"", r.value);
}

test "string escape backslash" {
    const P = struct { value: []const u8 };
    const r = parseProps(P, testing.allocator, "[\"path\\\\to\\\\file\"]");
    defer testing.allocator.free(r.value);
    try testing.expectEqualStrings("path\\to\\file", r.value);
}

test "string unicode" {
    const P = struct { value: []const u8 };
    const r = parseProps(P, testing.allocator, "[\"Hello 世界\"]");
    defer testing.allocator.free(r.value);
    try testing.expectEqualStrings("Hello 世界", r.value);
}

test "string emoji" {
    const P = struct { value: []const u8 };
    const r = parseProps(P, testing.allocator, "[\"Hello 👋\"]");
    defer testing.allocator.free(r.value);
    try testing.expectEqualStrings("Hello 👋", r.value);
}

// ============================================================================
// Optional Tests
// ============================================================================

test "optional null" {
    const r = parseProps(OptionalProps, testing.allocator, "[42,null,null]");
    try testing.expectEqual(@as(i32, 42), r.required);
    try testing.expect(r.optional_int == null);
    try testing.expect(r.optional_str == null);
}

test "optional int present" {
    const r = parseProps(OptionalProps, testing.allocator, "[42,100,null]");
    try testing.expectEqual(@as(i32, 100), r.optional_int.?);
}

test "optional string present" {
    const r = parseProps(OptionalProps, testing.allocator, "[42,null,\"hello\"]");
    defer if (r.optional_str) |s| testing.allocator.free(s);
    try testing.expectEqualStrings("hello", r.optional_str.?);
}

test "optional all present" {
    const r = parseProps(OptionalProps, testing.allocator, "[42,100,\"hello\"]");
    defer if (r.optional_str) |s| testing.allocator.free(s);
    try testing.expectEqual(@as(i32, 100), r.optional_int.?);
    try testing.expectEqualStrings("hello", r.optional_str.?);
}

// ============================================================================
// Nested Struct Tests
// ============================================================================

test "nested struct" {
    const r = parseProps(NestedProps, testing.allocator, "[10,[42,true],false]");
    try testing.expectEqual(@as(i32, 10), r.outer_val);
    try testing.expectEqual(@as(i32, 42), r.inner.value);
    try testing.expect(r.inner.flag and !r.outer_flag);
}

test "nested negative" {
    const r = parseProps(NestedProps, testing.allocator, "[0,[-99,false],true]");
    try testing.expectEqual(@as(i32, -99), r.inner.value);
    try testing.expect(!r.inner.flag and r.outer_flag);
}

test "deeply nested" {
    const Inner = struct { value: i32 };
    const Middle = struct { inner: Inner };
    const Outer = struct { middle: Middle };
    const r = parseProps(Outer, testing.allocator, "[[[42]]]");
    try testing.expectEqual(@as(i32, 42), r.middle.inner.value);
}

// ============================================================================
// Array Tests
// ============================================================================

test "array int" {
    const r = parseProps(ArrayProps, testing.allocator, "[[1,2,3],[true,false]]");
    try testing.expectEqual(@as(i32, 1), r.scores[0]);
    try testing.expectEqual(@as(i32, 2), r.scores[1]);
    try testing.expectEqual(@as(i32, 3), r.scores[2]);
}

test "array negative" {
    const r = parseProps(ArrayProps, testing.allocator, "[[-1,-2,-3],[false,true]]");
    try testing.expectEqual(@as(i32, -1), r.scores[0]);
    try testing.expectEqual(@as(i32, -2), r.scores[1]);
}

// ============================================================================
// Enum Tests
// ============================================================================

test "enum first" {
    const r = parseProps(EnumProps, testing.allocator, "[0,42]");
    try testing.expectEqual(Status.pending, r.status);
}

test "enum middle" {
    const r = parseProps(EnumProps, testing.allocator, "[1,42]");
    try testing.expectEqual(Status.active, r.status);
}

test "enum last" {
    const r = parseProps(EnumProps, testing.allocator, "[2,42]");
    try testing.expectEqual(Status.completed, r.status);
}

// ============================================================================
// Complex Integration Tests
// ============================================================================

test "complex all types" {
    const json = "[42,-100,0,3.14,-2.5,true,false,\"Hello\",\"World\",null,null,[10,true],[1,2,3],1]";
    const r = parseProps(ComplexProps, testing.allocator, json);
    defer testing.allocator.free(r.label);
    defer testing.allocator.free(r.escaped_str);

    try testing.expectEqual(@as(i32, 42), r.initial);
    try testing.expectEqual(@as(i32, -100), r.negative);
    try testing.expectApproxEqAbs(@as(f32, 3.14), r.float_val, 0.01);
    try testing.expect(r.shared and !r.disabled);
    try testing.expectEqualStrings("Hello", r.label);
    try testing.expect(r.optional_int == null);
    try testing.expectEqual(@as(i32, 10), r.nested.value);
    try testing.expectEqual(Status.active, r.status);
}

test "complex with optionals" {
    const json = "[42,-100,0,3.14,-2.5,true,false,\"Label\",\"Escaped\\n\",99,\"opt\",[0,false],[0,0,0],0]";
    const r = parseProps(ComplexProps, testing.allocator, json);
    defer testing.allocator.free(r.label);
    defer testing.allocator.free(r.escaped_str);
    defer if (r.optional_str) |s| testing.allocator.free(s);

    try testing.expectEqualStrings("Escaped\n", r.escaped_str);
    try testing.expectEqual(@as(i32, 99), r.optional_int.?);
    try testing.expectEqualStrings("opt", r.optional_str.?);
}

// ============================================================================
// Whitespace Tests
// ============================================================================

test "whitespace spaces" {
    const r = parseProps(SimpleProps, testing.allocator, "[ 42 , true ]");
    try testing.expectEqual(@as(i32, 42), r.count);
}

test "whitespace newlines" {
    const r = parseProps(SimpleProps, testing.allocator, "[\n42\n,\ntrue\n]");
    try testing.expectEqual(@as(i32, 42), r.count);
}

test "whitespace mixed" {
    const r = parseProps(SimpleProps, testing.allocator, "[ \n\t42 , \n\ttrue ]");
    try testing.expectEqual(@as(i32, 42), r.count);
}

// ============================================================================
// Edge Cases
// ============================================================================

test "null input" {
    const r = parseProps(SimpleProps, testing.allocator, null);
    try testing.expectEqual(@as(i32, 0), r.count);
    try testing.expect(!r.enabled);
}

test "parser direct" {
    const P = struct { x: i32, y: i32 };
    var parser = PropsParser.init("[10,20]");
    const r = try parser.parse(P, testing.allocator);
    try testing.expectEqual(@as(i32, 10), r.x);
    try testing.expectEqual(@as(i32, 20), r.y);
}

test "parser error" {
    const P = struct { value: i32 };
    var parser = PropsParser.init("42"); // Missing bracket
    try testing.expectError(error.ExpectedArrayStart, parser.parse(P, testing.allocator));
}
