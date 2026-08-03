//! Active ZLS backing implementation. Only imported when `build_options.enable_zls`.

const std = @import("std");
const builtin = @import("builtin");
const zls = @import("zls");
const lsp = @import("lsp");
const Handler = @import("../../Handler.zig");
const Zls = @import("../Zls.zig");

const request_methods = [_][]const u8{
    "initialize",
    "shutdown",
    "textDocument/willSaveWaitUntil",
    "textDocument/semanticTokens/full",
    "textDocument/semanticTokens/range",
    "textDocument/inlayHint",
    "textDocument/completion",
    "textDocument/signatureHelp",
    "textDocument/definition",
    "textDocument/typeDefinition",
    "textDocument/implementation",
    "textDocument/declaration",
    "textDocument/hover",
    "textDocument/documentSymbol",
    "textDocument/formatting",
    "textDocument/rename",
    "textDocument/prepareRename",
    "textDocument/references",
    "textDocument/documentHighlight",
    "textDocument/codeAction",
    "textDocument/foldingRange",
    "textDocument/selectionRange",
};

const notification_methods = [_][]const u8{
    "initialized",
    "exit",
    "textDocument/didOpen",
    "textDocument/didChange",
    "textDocument/didSave",
    "textDocument/didClose",
    "workspace/didChangeWatchedFiles",
    "workspace/didChangeWorkspaceFolders",
    "workspace/didChangeConfiguration",
};

const Impl = struct {
    allocator: std.mem.Allocator,
    server: *zls.Server,
    config_manager: *zls.configuration.Manager,
};

const vtable: Handler.VTable = .{
    .destroy = destroy,
    .request = request,
    .notification = notification,
    .onResponse = onResponse,
};

pub fn create(options: Zls.CreateOptions) Zls.CreateError!Zls.Backing {
    const allocator = options.allocator;

    const global_cache_path: ?[]const u8 = blk: {
        const home = options.environ_map.get("HOME") orelse break :blk null;
        const cache_suffix = if (builtin.os.tag == .macos) "Library/Caches/zls" else ".cache/zls";
        break :blk std.fs.path.join(allocator, &.{ home, cache_suffix }) catch null;
    };
    defer if (global_cache_path) |p| allocator.free(p);

    const config_manager = try allocator.create(zls.configuration.Manager);
    errdefer allocator.destroy(config_manager);

    config_manager.* = zls.configuration.Manager.init(options.io, allocator, options.environ_map) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Unexpected => return error.Unexpected,
    };
    errdefer config_manager.deinit();

    const zx_module_path: ?[]const u8 = blk: {
        if (options.zx_module) |p| if (p.len > 0) break :blk p;
        if (options.environ_map.get("ZX_MODULE_PATH")) |p| if (p.len > 0) break :blk p;
        break :blk null;
    };
    try config_manager.setConfiguration(.frontend, &.{
        .import_extensions = &.{"zx"},
        .modules = if (zx_module_path) |path| &.{
            .{
                .name = "zx",
                .path = path,
            },
        } else &.{},
    });

    const server = try zls.Server.create(.{
        .io = options.io,
        .allocator = allocator,
        .transport = @ptrCast(options.transport),
        .config_manager = config_manager,
    });
    errdefer zls.Server.destroy(server);

    const impl = try allocator.create(Impl);
    errdefer allocator.destroy(impl);
    impl.* = .{
        .allocator = allocator,
        .server = server,
        .config_manager = config_manager,
    };

    return .{
        .ptr = impl,
        .vtable = &vtable,
    };
}

fn destroy(ptr: *anyopaque) void {
    const impl: *Impl = @ptrCast(@alignCast(ptr));
    const allocator = impl.allocator;
    zls.Server.destroy(impl.server);
    impl.config_manager.deinit();
    allocator.destroy(impl.config_manager);
    allocator.destroy(impl);
}

fn request(
    ptr: *anyopaque,
    arena: std.mem.Allocator,
    method: []const u8,
    params: *const anyopaque,
    result: *anyopaque,
) anyerror!void {
    const impl: *Impl = @ptrCast(@alignCast(ptr));
    inline for (request_methods) |m| {
        if (std.mem.eql(u8, method, m)) {
            const P = zls.lsp.ParamsType(m);
            const R = zls.lsp.ResultType(m);
            const p: *const P = @ptrCast(@alignCast(params));
            const r: *R = @ptrCast(@alignCast(result));
            r.* = impl.server.sendRequestSync(arena, m, p.*) catch |err| {
                std.log.err("zls {s} failed: {}", .{ m, err });
                return;
            };
            return;
        }
    }
}

fn notification(
    ptr: *anyopaque,
    arena: std.mem.Allocator,
    method: []const u8,
    params: *const anyopaque,
) anyerror!void {
    const impl: *Impl = @ptrCast(@alignCast(ptr));
    inline for (notification_methods) |m| {
        if (std.mem.eql(u8, method, m)) {
            const P = zls.lsp.ParamsType(m);
            const p: *const P = @ptrCast(@alignCast(params));
            impl.server.sendNotificationSync(arena, m, p.*) catch |err| {
                std.log.err("zls {s} failed: {}", .{ m, err });
            };
            return;
        }
    }
}

fn onResponse(
    ptr: *anyopaque,
    arena: std.mem.Allocator,
    response: lsp.JsonRPCMessage.Response,
) void {
    const impl: *Impl = @ptrCast(@alignCast(ptr));
    const json_message = std.json.Stringify.valueAlloc(
        arena,
        lsp.JsonRPCMessage{ .response = response },
        .{ .emit_null_optional_fields = false },
    ) catch |err| {
        std.log.err("zls onResponse stringify failed: {}", .{err});
        return;
    };
    const reply = impl.server.sendJsonMessageSync(json_message) catch |err| {
        std.log.err("zls sendJsonMessageSync failed: {}", .{err});
        return;
    };
    if (reply) |r| impl.server.allocator.free(r);
}
