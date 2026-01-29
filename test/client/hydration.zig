const std = @import("std");
const testing = std.testing;
const zx = @import("zx");

/// Test the props hydration parser (zx.hydration)
const parseProps = zx.hydration.parseProps;
const serializeProps = zx.prop.serialize;
const PropsParser = zx.hydration.PropsParser;

// ============================================================================
// Test Fixtures
// ============================================================================

const Status = enum { pending, active, completed };
const SearchContent = struct { title: []const u8, url: []const u8, content: []const u8 };
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

test "complex large data" {
    const content_parsed: std.json.Parsed([]SearchContent) = std.json.parseFromSlice([]SearchContent, testing.allocator, search_txt, .{}) catch unreachable;
    defer content_parsed.deinit();
    const content_p = content_parsed.value;
    std.log.info("\n{d}\n", .{content_p.len});

    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();

    try serializeProps([]SearchContent, content_p, &aw.writer);

    const data = aw.written();
    try testing.expect(data.len > 0);
    // Positional format outputs structs as arrays, so we expect [["title","url","content"],...]
    // The first SearchContent's title is "std.Io", so positional format starts with [["std.Io",...
    try testing.expect(std.mem.startsWith(u8, data, "[[\"std.Io\""));
    std.log.err("\nData: {s}\n", .{data});
}

// ============================================================================
// Serializer Tests
// ============================================================================

fn serialize(comptime T: type, value: T) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer aw.deinit();
    try serializeProps(T, value, &aw.writer);
    return testing.allocator.dupe(u8, aw.written());
}

test "serialize int positive" {
    const P = struct { value: i32 };
    const data = try serialize(P, .{ .value = 42 });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[42]", data);
}

test "serialize int negative" {
    const P = struct { value: i32 };
    const data = try serialize(P, .{ .value = -100 });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[-100]", data);
}

test "serialize int zero" {
    const P = struct { value: i32 };
    const data = try serialize(P, .{ .value = 0 });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[0]", data);
}

test "serialize multiple ints" {
    const P = struct { a: i32, b: i32, c: i32 };
    const data = try serialize(P, .{ .a = 1, .b = -2, .c = 0 });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[1,-2,0]", data);
}

test "serialize float positive" {
    const P = struct { value: f32 };
    const data = try serialize(P, .{ .value = 3.14 });
    defer testing.allocator.free(data);
    try testing.expect(std.mem.startsWith(u8, data, "[3.14"));
}

test "serialize float negative" {
    const P = struct { value: f32 };
    const data = try serialize(P, .{ .value = -2.5 });
    defer testing.allocator.free(data);
    try testing.expect(std.mem.startsWith(u8, data, "[-2.5"));
}

test "serialize bool true" {
    const P = struct { value: bool };
    const data = try serialize(P, .{ .value = true });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[true]", data);
}

test "serialize bool false" {
    const P = struct { value: bool };
    const data = try serialize(P, .{ .value = false });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[false]", data);
}

test "serialize string simple" {
    const P = struct { value: []const u8 };
    const data = try serialize(P, .{ .value = "hello" });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[\"hello\"]", data);
}

test "serialize string empty" {
    const P = struct { value: []const u8 };
    const data = try serialize(P, .{ .value = "" });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[\"\"]", data);
}

test "serialize string with spaces" {
    const P = struct { value: []const u8 };
    const data = try serialize(P, .{ .value = "hello world" });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[\"hello world\"]", data);
}

test "serialize string escape newline" {
    const P = struct { value: []const u8 };
    const data = try serialize(P, .{ .value = "line1\nline2" });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[\"line1\\nline2\"]", data);
}

test "serialize string escape tab" {
    const P = struct { value: []const u8 };
    const data = try serialize(P, .{ .value = "col1\tcol2" });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[\"col1\\tcol2\"]", data);
}

test "serialize string escape quote" {
    const P = struct { value: []const u8 };
    const data = try serialize(P, .{ .value = "say \"hello\"" });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[\"say \\\"hello\\\"\"]", data);
}

test "serialize string escape backslash" {
    const P = struct { value: []const u8 };
    const data = try serialize(P, .{ .value = "path\\to\\file" });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[\"path\\\\to\\\\file\"]", data);
}

test "serialize string escape carriage return" {
    const P = struct { value: []const u8 };
    const data = try serialize(P, .{ .value = "line1\rline2" });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[\"line1\\rline2\"]", data);
}

test "serialize string unicode" {
    const P = struct { value: []const u8 };
    const data = try serialize(P, .{ .value = "Hello 世界" });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[\"Hello 世界\"]", data);
}

test "serialize string emoji" {
    const P = struct { value: []const u8 };
    const data = try serialize(P, .{ .value = "Hello 👋" });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[\"Hello 👋\"]", data);
}

test "serialize optional null" {
    const P = struct { value: ?i32 };
    const data = try serialize(P, .{ .value = null });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[null]", data);
}

test "serialize optional present int" {
    const P = struct { value: ?i32 };
    const data = try serialize(P, .{ .value = 42 });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[42]", data);
}

test "serialize optional present string" {
    const P = struct { value: ?[]const u8 };
    const data = try serialize(P, .{ .value = "hello" });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[\"hello\"]", data);
}

test "serialize optional string null" {
    const P = struct { value: ?[]const u8 };
    const data = try serialize(P, .{ .value = null });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[null]", data);
}

test "serialize nested struct" {
    const Inner = struct { x: i32 };
    const Outer = struct { inner: Inner };
    const data = try serialize(Outer, .{ .inner = .{ .x = 42 } });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[[42]]", data);
}

test "serialize deeply nested struct" {
    const A = struct { val: i32 };
    const B = struct { a: A };
    const C = struct { b: B };
    const data = try serialize(C, .{ .b = .{ .a = .{ .val = 123 } } });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[[[123]]]", data);
}

test "serialize nested with multiple fields" {
    const data = try serialize(NestedProps, .{
        .outer_val = 10,
        .inner = .{ .value = 42, .flag = true },
        .outer_flag = false,
    });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[10,[42,true],false]", data);
}

test "serialize array int" {
    const P = struct { values: [3]i32 };
    const data = try serialize(P, .{ .values = .{ 1, 2, 3 } });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[[1,2,3]]", data);
}

test "serialize array bool" {
    const P = struct { flags: [2]bool };
    const data = try serialize(P, .{ .flags = .{ true, false } });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[[true,false]]", data);
}

test "serialize array negative" {
    const P = struct { values: [3]i32 };
    const data = try serialize(P, .{ .values = .{ -1, -2, -3 } });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[[-1,-2,-3]]", data);
}

test "serialize enum first" {
    const data = try serialize(EnumProps, .{ .status = .pending, .value = 42 });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[0,42]", data);
}

test "serialize enum middle" {
    const data = try serialize(EnumProps, .{ .status = .active, .value = 42 });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[1,42]", data);
}

test "serialize enum last" {
    const data = try serialize(EnumProps, .{ .status = .completed, .value = 42 });
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[2,42]", data);
}

test "serialize slice of structs" {
    const Item = struct { id: i32, name: []const u8 };
    const items: []const Item = &.{
        .{ .id = 1, .name = "first" },
        .{ .id = 2, .name = "second" },
    };
    const data = try serialize([]const Item, items);
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[[1,\"first\"],[2,\"second\"]]", data);
}

test "serialize slice of ints" {
    const values: []const i32 = &.{ 10, 20, 30 };
    const data = try serialize([]const i32, values);
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[10,20,30]", data);
}

test "serialize empty slice" {
    const items: []const i32 = &.{};
    const data = try serialize([]const i32, items);
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("[]", data);
}

test "serialize complex props" {
    const props = ComplexProps{
        .initial = 42,
        .negative = -100,
        .zero_val = 0,
        .float_val = 3.14,
        .negative_float = -2.5,
        .shared = true,
        .disabled = false,
        .label = "Hello",
        .escaped_str = "World\n",
        .optional_int = null,
        .optional_str = null,
        .nested = .{ .value = 10, .flag = true },
        .scores = .{ 1, 2, 3 },
        .status = .active,
    };
    const data = try serialize(ComplexProps, props);
    defer testing.allocator.free(data);
    // Verify structure: starts and ends correctly, contains expected substrings
    try testing.expect(std.mem.startsWith(u8, data, "[42,-100,0,"));
    try testing.expect(std.mem.indexOf(u8, data, "\"Hello\"") != null);
    try testing.expect(std.mem.indexOf(u8, data, "\"World\\n\"") != null);
    try testing.expect(std.mem.indexOf(u8, data, "[10,true]") != null);
    try testing.expect(std.mem.indexOf(u8, data, "[1,2,3]") != null);
    try testing.expect(std.mem.endsWith(u8, data, ",1]"));
}

test "serialize roundtrip simple" {
    // Serialize then parse, should get same values
    const original = SimpleProps{ .count = 42, .enabled = true };
    const data = try serialize(SimpleProps, original);
    defer testing.allocator.free(data);

    const parsed = parseProps(SimpleProps, testing.allocator, data);
    try testing.expectEqual(original.count, parsed.count);
    try testing.expectEqual(original.enabled, parsed.enabled);
}

test "serialize roundtrip nested" {
    const original = NestedProps{
        .outer_val = 10,
        .inner = .{ .value = 42, .flag = true },
        .outer_flag = false,
    };
    const data = try serialize(NestedProps, original);
    defer testing.allocator.free(data);

    const parsed = parseProps(NestedProps, testing.allocator, data);
    try testing.expectEqual(original.outer_val, parsed.outer_val);
    try testing.expectEqual(original.inner.value, parsed.inner.value);
    try testing.expectEqual(original.inner.flag, parsed.inner.flag);
    try testing.expectEqual(original.outer_flag, parsed.outer_flag);
}

test "serialize roundtrip array" {
    const original = ArrayProps{
        .scores = .{ 10, 20, 30 },
        .flags = .{ true, false },
    };
    const data = try serialize(ArrayProps, original);
    defer testing.allocator.free(data);

    const parsed = parseProps(ArrayProps, testing.allocator, data);
    try testing.expectEqual(original.scores[0], parsed.scores[0]);
    try testing.expectEqual(original.scores[1], parsed.scores[1]);
    try testing.expectEqual(original.scores[2], parsed.scores[2]);
    try testing.expectEqual(original.flags[0], parsed.flags[0]);
    try testing.expectEqual(original.flags[1], parsed.flags[1]);
}

test "serialize roundtrip enum" {
    const original = EnumProps{ .status = .completed, .value = 99 };
    const data = try serialize(EnumProps, original);
    defer testing.allocator.free(data);

    const parsed = parseProps(EnumProps, testing.allocator, data);
    try testing.expectEqual(original.status, parsed.status);
    try testing.expectEqual(original.value, parsed.value);
}

test "serialize roundtrip optional null" {
    const original = OptionalProps{ .required = 42, .optional_int = null, .optional_str = null };
    const data = try serialize(OptionalProps, original);
    defer testing.allocator.free(data);

    const parsed = parseProps(OptionalProps, testing.allocator, data);
    try testing.expectEqual(original.required, parsed.required);
    try testing.expect(parsed.optional_int == null);
    try testing.expect(parsed.optional_str == null);
}

test "serialize roundtrip optional present" {
    const original = OptionalProps{ .required = 42, .optional_int = 100, .optional_str = "hello" };
    const data = try serialize(OptionalProps, original);
    defer testing.allocator.free(data);

    const parsed = parseProps(OptionalProps, testing.allocator, data);
    defer if (parsed.optional_str) |s| testing.allocator.free(s);
    try testing.expectEqual(original.required, parsed.required);
    try testing.expectEqual(original.optional_int, parsed.optional_int);
    try testing.expectEqualStrings("hello", parsed.optional_str.?);
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

const search_txt =
    \\[{"title":"std.Io","url":"/std/Io","content":"A cross-platform interface that abstracts all I/O operations and concurrency, including file system, networking, processes, time, randomness, async/await, concurrent queues, synchronization primitives, and memory mapped files."},{"title":"AnyFuture","url":"/std/Io/AnyFuture","content":"Type-erased future for async operations"},{"title":"CancelProtection","url":"/std/Io/CancelProtection","content":"Protection state for cancelation"},{"title":"Clock","url":"/std/Io/Clock","content":"Clock source for time operations"},{"title":"Condition","url":"/std/Io/Condition","content":"Condition variable for synchronization"},{"title":"Dir","url":"/std/Io/Dir","content":"Directory handle"},{"title":"Duration","url":"/std/Io/Duration","content":"Time duration representation"},{"title":"Event","url":"/std/Io/Event","content":"Event signaling primitive"},{"title":"File","url":"/std/Io/File","content":"File handle"},{"title":"Future","url":"/std/Io/Future","content":"Typed future for async results"},{"title":"Group","url":"/std/Io/Group","content":"Wait group for concurrent operations"},{"title":"Mutex","url":"/std/Io/Mutex","content":"Mutual exclusion lock"},{"title":"Queue","url":"/std/Io/Queue","content":"Concurrent queue"},{"title":"Reader","url":"/std/Io/Reader","content":"Buffered reader interface"},{"title":"Writer","url":"/std/Io/Writer","content":"Buffered writer interface"},{"title":"net","url":"/std/Io/net","content":"Networking functionality including TCP, UDP, and address resolution"},{"title":"async","url":"/std/Io/async","content":"Calls function with args, return value available after await"},{"title":"checkCancel","url":"/std/Io/checkCancel","content":"Acts as a pure cancelation point"},{"title":"concurrent","url":"/std/Io/concurrent","content":"Calls function allowing caller to progress while waiting"},{"title":"futexWait","url":"/std/Io/futexWait","content":"Atomically checks value and blocks until woken"},{"title":"futexWake","url":"/std/Io/futexWake","content":"Unblocks pending futex waits"},{"title":"lockStderr","url":"/std/Io/lockStderr","content":"Coordinates application-level writes to stderr"},{"title":"poll","url":"/std/Io/poll","content":"Creates a poller for monitoring file descriptors"},{"title":"random","url":"/std/Io/random","content":"Obtains cryptographically secure random bytes"},{"title":"select","url":"/std/Io/select","content":"Waits on multiple futures, returns when any completes"},{"title":"sleep","url":"/std/Io/sleep","content":"Suspends execution for the specified duration"},{"title":"Overview","url":"/std/Io#overview","content":"What it represents A cross-platform interface that abstracts all I/O operations and concurrency. This interface allows programmers to write optimal, reusable code while participating in these operations. Category:std namespace › Io struct Source:lib/std/Io.zig "},{"title":"Capabilities","url":"/std/Io#capabilities","content":"What Io provides The Io struct provides a unified interface for a wide range of system operations: file system — read, write, and manage files and directories networking — TCP, UDP, and other network protocols processes — spawn and manage child processes time and sleeping — timers, delays, and clock access randomness — cryptographic and general-purpose random number generation async, await, concurrent, and cancel — asynchronous programming primitives concurrent queues — thread-safe data structures wait groups and select — synchronization mechanisms mutexes, futexes, events, and conditions — low-level synchronization memory mapped files — efficient file I/O via memory mapping "},{"title":"Fields","url":"/std/Io#fields","content":"Struct fields userdata:?*anyopaque — User-defined data pointer for custom context vtable:*const VTable — Virtual table containing function pointers for I/O operations "},{"title":"Types","url":"/std/Io#types","content":"Associated types The Io struct defines many associated types for different I/O operations: AnyFuture — Type-erased future for async operations CancelProtection — Protection state for cancelation Clock — Clock source for time operations Condition — Condition variable for synchronization Dir — Directory handle Duration — Time duration representation Event — Event signaling primitive Evented — Event-based I/O wrapper File — File handle Future — Typed future for async results Group — Wait group for concurrent operations IoUring — Linux io_uring backend Kqueue — BSD/macOS kqueue backend Limit — Resource limits LockedStderr — Locked stderr for coordinated writes Mutex — Mutual exclusion lock PollFiles — File polling interface Poller — Platform-specific poller Queue — Concurrent queue Reader — Buffered reader interface Select — Select operation for multiple futures SelectUnion — Union type for select results Terminal — Terminal I/O interface Threaded — Threaded I/O backend Timeout — Timeout configuration Timestamp — Point in time representation TypeErasedQueue — Type-erased concurrent queue VTable — Virtual function table Writer — Buffered writer interface "},{"title":"Namespaces","url":"/std/Io#namespaces","content":"Sub-namespaces net:Networking functionality including TCP, UDP, and address resolution "},{"title":"Functions","url":"/std/Io#functions","content":"Public API methods The Io struct provides many functions for asynchronous I/O and concurrency: async:Calls function with args, such that the return value is not guaranteed to be available until await is called. checkCancel:Acts as a pure cancelation point and does nothing else. Returns error.Canceled if there is an outstanding non-blocked cancelation request. concurrent:Calls function with args, allowing the caller to progress while waiting for any Io operations. futexWait:Atomically checks if the value at ptr equals expected, and if so, blocks until woken. futexWaitTimeout:Same as futexWait, except also unblocks if timeout expires. Spurious wakeups are possible. futexWaitUncancelable:Same as futexWait, except does not introduce a cancelation point. futexWake:Unblocks pending futex waits on ptr, up to a limit of max_waiters calls. lockStderr:For application-level writes to stderr. Coordinates with debug-level writes ignorant of Io interface. poll:Creates a poller for monitoring multiple file descriptors. random:Obtains entropy from a cryptographically secure pseudo-random number generator. randomSecure:Obtains cryptographically secure entropy from outside the process. recancel:Re-arms the cancelation request so error.Canceled will be returned from the next cancelation point. select:Waits on multiple futures, returning when any one completes. sleep:Suspends execution for the specified duration. swapCancelProtection:Updates the current task's cancel protection state. tryLockStderr:Same as lockStderr but non-blocking. unlockStderr:Unlocks stderr after a lockStderr call. "},{"title":"Error Sets","url":"/std/Io#error-sets","content":"Possible errors The Io functions may return these error sets: Cancelable:Operation was canceled via cancelation point ConcurrentError:Error during concurrent operation execution QueueClosedError:Attempted operation on a closed queue RandomSecureError:Failed to obtain secure random bytes SleepError:Error during sleep operation UnexpectedError:Unexpected system error occurred "}]
;
