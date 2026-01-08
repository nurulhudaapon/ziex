const std = @import("std");
const zx = @import("zx");
const Request = zx.Request;
const Response = zx.Response;
const PageContext = zx.PageContext;
const LayoutContext = zx.LayoutContext;
const NotFoundContext = zx.NotFoundContext;
const ErrorContext = zx.ErrorContext;

// --- Context Type Aliases --- //

test "PageContext: is same as LayoutContext" {
    try std.testing.expect(PageContext == LayoutContext);
}

test "PageContext: is same as NotFoundContext" {
    try std.testing.expect(PageContext == NotFoundContext);
}

// --- PageContext --- //

test "PageContext: has request field" {
    var buffer: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const alloc = fba.allocator();

    const req = (Request.Builder{
        .url = "/test",
        .method = .POST,
        .arena = alloc,
    }).build();

    const res = (Response.Builder{
        .status = 200,
        .arena = alloc,
    }).build();

    const ctx = PageContext.init(req, res, alloc);

    try std.testing.expectEqualStrings("/test", ctx.request.url);
    try std.testing.expectEqual(Request.Method.POST, ctx.request.method);
}

test "PageContext: has response field" {
    var buffer: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const alloc = fba.allocator();

    const req = (Request.Builder{ .arena = alloc }).build();
    const res = (Response.Builder{
        .status = 201,
        .arena = alloc,
    }).build();

    const ctx = PageContext.init(req, res, alloc);

    try std.testing.expectEqual(@as(u16, 201), ctx.response.status);
    try std.testing.expect(ctx.response.ok);
    try std.testing.expectEqualStrings("Created", ctx.response.statusText);
}

test "PageContext: has allocator and arena fields" {
    var buffer: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const alloc = fba.allocator();

    const req = (Request.Builder{ .arena = alloc }).build();
    const res = (Response.Builder{ .arena = alloc }).build();
    const ctx = PageContext.init(req, res, alloc);

    // Verify fields are accessible
    _ = ctx.allocator;
    _ = ctx.arena;
}

test "PageContext: parent_ctx is null by default" {
    var buffer: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const alloc = fba.allocator();

    const req = (Request.Builder{ .arena = alloc }).build();
    const res = (Response.Builder{ .arena = alloc }).build();
    const ctx = PageContext.init(req, res, alloc);

    try std.testing.expect(ctx.parent_ctx == null);
}

// --- ErrorContext --- //

test "ErrorContext: has error field" {
    var buffer: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const alloc = fba.allocator();

    const req = (Request.Builder{ .arena = alloc }).build();
    const res = (Response.Builder{ .arena = alloc }).build();
    const err = error.OutOfMemory;

    const ctx = ErrorContext.init(req, res, alloc, err);

    try std.testing.expectEqual(error.OutOfMemory, ctx.err);
}

test "ErrorContext: has request and response fields" {
    var buffer: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const alloc = fba.allocator();

    const req = (Request.Builder{
        .url = "/error-page",
        .arena = alloc,
    }).build();

    const res = (Response.Builder{
        .status = 500,
        .arena = alloc,
    }).build();

    const ctx = ErrorContext.init(req, res, alloc, error.Unexpected);

    try std.testing.expectEqualStrings("/error-page", ctx.request.url);
    try std.testing.expectEqual(@as(u16, 500), ctx.response.status);
}

test "ErrorContext: has allocator and arena fields" {
    var buffer: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const alloc = fba.allocator();

    const req = (Request.Builder{ .arena = alloc }).build();
    const res = (Response.Builder{ .arena = alloc }).build();
    const ctx = ErrorContext.init(req, res, alloc, error.Unexpected);

    _ = ctx.allocator;
    _ = ctx.arena;
}
