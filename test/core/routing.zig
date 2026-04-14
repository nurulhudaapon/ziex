const std = @import("std");
const zx = @import("zx");

const Request = zx.server.Request;
const Response = zx.server.Response;
const PageContext = zx.PageContext;
const LayoutContext = zx.LayoutContext;
const NotFoundContext = zx.NotFoundContext;
const ErrorContext = zx.ErrorContext;
const ServerMeta = zx.server.ServerMeta;

const AppCtx = struct { port: u16 };
const StateCtx = struct { count: i32 };

var seen_page_app_port: u16 = 0;
var seen_page_state_count: i32 = 0;

var seen_layout_app_port: u16 = 0;
var seen_layout_state_count: i32 = 0;

const PageModule = struct {
    pub fn Page(ctx: zx.PageContext, app: AppCtx, state: StateCtx) zx.Component {
        _ = ctx;
        seen_page_app_port = app.port;
        seen_page_state_count = state.count;
        return .{ .text = "ok" };
    }
};

const LayoutModule = struct {
    pub fn Layout(ctx: zx.LayoutContext, child: zx.Component, app: AppCtx, state: StateCtx) zx.Component {
        _ = ctx;
        seen_layout_app_port = app.port;
        seen_layout_state_count = state.count;
        return child;
    }
};

const OptionalPageModule = struct {
    pub var saw_null: bool = false;

    pub fn Page(ctx: zx.PageContext, app: ?*const AppCtx) zx.Component {
        _ = ctx;
        saw_null = (app == null);
        return .{ .text = "ok" };
    }
};

fn makeReqRes(alloc: std.mem.Allocator) struct { req: Request, res: Response } {
    const req = (Request.Builder{ .url = "/", .arena = alloc }).build();
    const res = (Response.Builder{ .arena = alloc }).build();
    return .{ .req = req, .res = res };
}

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

test "ServerMeta.page injects app/state positional values" {
    var buffer: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const alloc = fba.allocator();

    const rr = makeReqRes(alloc);
    const page_fn = ServerMeta.page(PageModule);
    const ctx = zx.PageContext.init(rr.req, rr.res, alloc);

    var app = AppCtx{ .port = 5588 };
    var state = StateCtx{ .count = 42 };

    _ = try page_fn(ctx, @ptrCast(&app), @ptrCast(&state));

    try std.testing.expectEqual(@as(u16, 5588), seen_page_app_port);
    try std.testing.expectEqual(@as(i32, 42), seen_page_state_count);
}

test "ServerMeta.layout injects app/state positional values" {
    var buffer: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const alloc = fba.allocator();

    const rr = makeReqRes(alloc);
    const layout_fn = ServerMeta.layout(LayoutModule);
    const ctx = zx.LayoutContext.init(rr.req, rr.res, alloc);

    var app = AppCtx{ .port = 9000 };
    var state = StateCtx{ .count = 7 };
    const child = zx.Component{ .text = "child" };

    const out = layout_fn(ctx, child, @ptrCast(&app), @ptrCast(&state));
    _ = out;

    try std.testing.expectEqual(@as(u16, 9000), seen_layout_app_port);
    try std.testing.expectEqual(@as(i32, 7), seen_layout_state_count);
}

test "ServerMeta.page injects null for optional app parameter" {
    var buffer: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const alloc = fba.allocator();

    OptionalPageModule.saw_null = false;

    const rr = makeReqRes(alloc);
    const page_fn = ServerMeta.page(OptionalPageModule);
    const ctx = zx.PageContext.init(rr.req, rr.res, alloc);

    _ = try page_fn(ctx, null, null);

    try std.testing.expect(OptionalPageModule.saw_null);
}
