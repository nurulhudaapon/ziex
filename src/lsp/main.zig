comptime {
    @setEvalBranchQuota(100_000);
}

const std = @import("std");
const builtin = @import("builtin");
const zls = @import("zls");
const lsp = zls.lsp;
const zx = @import("zx");

const ByteRange = struct {
    start: usize,
    end: usize,
};

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main(init: std.process.Init) !void {
    const gpa, const is_debug = switch (builtin.os.tag) {
        .wasi, .freestanding => .{ std.heap.wasm_allocator, false },
        else => switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        },
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    @setEvalBranchQuota(100_000);

    var read_buffer: [256]u8 = undefined;
    var stdio_transport: lsp.Transport.Stdio = .init(&read_buffer, .stdin(), .stdout());
    const transport: *lsp.Transport = &stdio_transport.transport;

    const global_cache_path: ?[]const u8 = blk: {
        const home = init.minimal.environ.getAlloc(gpa, "HOME") catch break :blk null;
        defer gpa.free(home);
        const cache_suffix = if (builtin.os.tag == .macos) "Library/Caches/zls" else ".cache/zls";
        break :blk std.fs.path.join(gpa, &.{ home, cache_suffix }) catch null;
    };
    defer if (global_cache_path) |p| gpa.free(p);

    var cm = zls.configuration.Manager.init(init.io, gpa, init.environ_map) catch unreachable;

    try cm.setConfiguration(.frontend, &.{
        .global_cache_path = global_cache_path,
    });

    const zls_server = try zls.Server.create(.{
        .io = init.io,
        .allocator = gpa,
        .transport = transport,
        .config_manager = &cm,
    });

    var handler: Handler = .init(gpa, zls_server, transport, init.io);
    defer handler.deinit();

    lsp.basic_server.run(
        init.io,
        gpa,
        transport,
        &handler,
        std.log.err,
    ) catch |err| {
        if (err != error.EndOfStream) {
            return err;
        }
    };
}

const ZxFileState = struct {
    zig_uri: []const u8,
    source: []const u8,
    zx_block_ranges: []const ByteRange,

    fn deinit(self: *ZxFileState, allocator: std.mem.Allocator) void {
        allocator.free(self.zig_uri);
        allocator.free(self.source);
        allocator.free(self.zx_block_ranges);
    }
};

pub const Handler = struct {
    allocator: std.mem.Allocator,
    zls: *zls.Server,
    transport: *lsp.Transport,
    io: std.Io,
    offset_encoding: lsp.offsets.Encoding,
    zx_files: std.StringHashMap(ZxFileState),

    fn init(allocator: std.mem.Allocator, zls_server: *zls.Server, transport: *lsp.Transport, io: std.Io) Handler {
        return .{
            .allocator = allocator,
            .zls = zls_server,
            .transport = transport,
            .io = io,
            .offset_encoding = .@"utf-16",
            .zx_files = std.StringHashMap(ZxFileState).init(allocator),
        };
    }

    fn deinit(handler: *Handler) void {
        var it = handler.zx_files.iterator();
        while (it.next()) |entry| {
            handler.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(handler.allocator);
        }
        handler.zx_files.deinit();
        zls.Server.destroy(handler.zls);
        handler.* = undefined;
    }

    fn isZxUri(uri: []const u8) bool {
        return std.mem.endsWith(u8, uri, ".zx");
    }

    fn toZigUri(allocator: std.mem.Allocator, zx_uri: []const u8) ![]const u8 {
        return allocator.dupe(u8, zx_uri);
    }

    fn getZlsUri(handler: *Handler, uri: []const u8) []const u8 {
        _ = handler;
        return uri;
    }

    fn getEditorUri(handler: *Handler, uri: []const u8) []const u8 {
        _ = handler;
        return uri;
    }

    fn isByteSlice(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .pointer => |pointer| pointer.size == .slice and pointer.child == u8 and pointer.is_const,
            else => false,
        };
    }

    fn fieldLooksLikeUri(comptime name: []const u8) bool {
        return std.mem.eql(u8, name, "uri") or std.mem.indexOf(u8, name, "Uri") != null;
    }

    fn remapUrisInValue(handler: *Handler, value: anytype) void {
        const T = @TypeOf(value.*);
        switch (@typeInfo(T)) {
            .@"struct" => |info| inline for (info.fields) |field| {
                const field_ptr = &@field(value.*, field.name);
                if (comptime fieldLooksLikeUri(field.name) and isByteSlice(field.type)) {
                    @constCast(field_ptr).* = handler.getEditorUri(field_ptr.*);
                } else {
                    handler.remapUrisInValue(field_ptr);
                }
            },
            .@"union" => |info| {
                if (info.tag_type) |Tag| {
                    switch (value.*) {
                        inline else => |*payload, tag| {
                            _ = @as(Tag, tag);
                            handler.remapUrisInValue(payload);
                        },
                    }
                }
            },
            .optional => {
                if (value.*) |*payload| handler.remapUrisInValue(payload);
            },
            .pointer => |pointer| switch (pointer.size) {
                .slice => {
                    if (pointer.child == u8) return;
                    for (value.*) |*item| handler.remapUrisInValue(item);
                },
                else => {},
            },
            else => {},
        }
    }

    fn remapResponseUris(handler: *Handler, result: anytype) @TypeOf(result) {
        var remapped = result;
        handler.remapUrisInValue(&remapped);
        return remapped;
    }

    /// Resolve file:// URI to a filesystem path (strips the file:// prefix).
    fn uriToPath(uri: []const u8) ?[]const u8 {
        if (std.mem.startsWith(u8, uri, "file://")) return uri[7..];
        return null;
    }

    /// For each @import("*.zx") in source, ensure the referenced .zx file is opened in ZLS.
    /// This is a known issue with ZLS not auto opening imported files in some case.
    fn openZxImportsInZls(handler: *Handler, arena: std.mem.Allocator, document_uri: []const u8, source: []const u8) void {
        const doc_path = uriToPath(document_uri) orelse return;
        const doc_dir = std.fs.path.dirname(doc_path) orelse return;

        const needle = "@import(\"";
        var pos: usize = 0;
        while (std.mem.indexOfPos(u8, source, pos, needle)) |start| {
            const path_start = start + needle.len;
            if (std.mem.indexOfPos(u8, source, path_start, "\")")) |path_end| {
                const import_path = source[path_start..path_end];
                if (std.mem.endsWith(u8, import_path, ".zx")) {
                    handler.ensureZxFileOpenInZls(arena, doc_dir, import_path);
                }
                pos = path_end + 2;
            } else break;
        }
    }

    /// Open a .zx file in ZLS if not already tracked - reads from disk, transpiles to .zig, sends didOpen.
    /// For imported files we send transpiled .zig (not raw .zx) so ZLS can resolve exported types.
    fn ensureZxFileOpenInZls(handler: *Handler, arena: std.mem.Allocator, doc_dir: []const u8, rel_path: []const u8) void {
        const joined = std.fs.path.join(handler.allocator, &.{ doc_dir, rel_path }) catch return;
        defer handler.allocator.free(joined);

        const resolved_path = switch (builtin.os.tag) {
            .wasi, .freestanding => handler.allocator.dupe(u8, joined) catch return,
            else => std.Io.Dir.cwd().realPathFileAlloc(handler.io, joined, handler.allocator) catch return,
        };
        defer handler.allocator.free(resolved_path);

        const zx_uri = std.fmt.allocPrint(handler.allocator, "file://{s}", .{resolved_path}) catch return;
        defer handler.allocator.free(zx_uri);

        if (handler.zx_files.contains(zx_uri)) return;

        const content = std.Io.Dir.cwd().readFileAlloc(handler.io, resolved_path, handler.allocator, .limited(4 * 1024 * 1024)) catch return;
        defer handler.allocator.free(content);

        handler.storeAndDiagnose(zx_uri, content);

        const zig_uri = handler.getZlsUri(zx_uri);

        const source_z = handler.allocator.dupeZ(u8, content) catch return;
        defer handler.allocator.free(source_z);

        var parse_result = zx.Ast.parse(handler.allocator, source_z, .{}) catch null;
        defer if (parse_result) |*r| r.deinit(handler.allocator);

        const zls_text: []const u8 = if (parse_result) |r| r.zig_source else content;

        handler.openZxImportsInZls(arena, zx_uri, content);

        handler.zls.sendNotificationSync(arena, "textDocument/didOpen", .{
            .textDocument = .{
                .uri = zig_uri,
                .languageId = .{ .custom_value = "zig" },
                .version = @as(i32, 0),
                .text = zls_text,
            },
        }) catch {};
    }

    /// Store .zx file state and publish zx-specific diagnostics.
    fn storeAndDiagnose(handler: *Handler, uri: []const u8, source: []const u8) void {
        const source_z = handler.allocator.dupeZ(u8, source) catch return;
        defer handler.allocator.free(source_z);

        var result = zx.Ast.parse(handler.allocator, source_z, .{}) catch return;
        defer result.deinit(handler.allocator);

        handler.publishZxDiagnostics(uri, result.diagnostics) catch {};

        const zx_block_ranges = handler.collectZxBlockRanges(source) catch (handler.allocator.alloc(ByteRange, 0) catch return);

        const zig_uri = toZigUri(handler.allocator, uri) catch return;
        const uri_key = handler.allocator.dupe(u8, uri) catch {
            handler.allocator.free(zx_block_ranges);
            handler.allocator.free(zig_uri);
            return;
        };
        const source_owned = handler.allocator.dupe(u8, source) catch {
            handler.allocator.free(zx_block_ranges);
            handler.allocator.free(zig_uri);
            handler.allocator.free(uri_key);
            return;
        };

        if (handler.zx_files.fetchRemove(uri)) |old| {
            handler.allocator.free(old.key);
            var old_state = old.value;
            old_state.deinit(handler.allocator);
        }

        handler.zx_files.put(uri_key, .{
            .zig_uri = zig_uri,
            .source = source_owned,
            .zx_block_ranges = zx_block_ranges,
        }) catch {
            handler.allocator.free(zx_block_ranges);
            handler.allocator.free(zig_uri);
            handler.allocator.free(uri_key);
            handler.allocator.free(source_owned);
        };
    }

    fn collectZxBlockRanges(handler: *Handler, source: []const u8) ![]const ByteRange {
        var parse = try zx.Parse.parse(handler.allocator, source, .zx);
        defer parse.deinit(handler.allocator);

        var ranges = std.ArrayList(ByteRange).empty;
        defer ranges.deinit(handler.allocator);

        try collectZxBlockRangesNode(parse.tree.rootNode(), &ranges, handler.allocator);
        return try ranges.toOwnedSlice(handler.allocator);
    }

    fn collectZxBlockRangesNode(node: anytype, ranges: *std.ArrayList(ByteRange), allocator: std.mem.Allocator) !void {
        if (zx.Parse.NodeKind.fromNode(node) == .zx_block) {
            try ranges.append(allocator, .{
                .start = node.startByte(),
                .end = node.endByte(),
            });
            return;
        }

        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            const child = node.child(i) orelse continue;
            try collectZxBlockRangesNode(child, ranges, allocator);
        }
    }

    fn offsetInAnyRange(offset: usize, ranges: []const ByteRange) bool {
        for (ranges) |range| {
            if (offset >= range.start and offset < range.end) return true;
        }
        return false;
    }

    fn filterInlayHintsForZxBlocks(
        arena: std.mem.Allocator,
        hints: []const lsp.types.flat.InlayHint,
        state: *const ZxFileState,
    ) ![]const lsp.types.flat.InlayHint {
        if (hints.len == 0 or state.zx_block_ranges.len == 0) return hints;

        var filtered = std.ArrayList(lsp.types.flat.InlayHint).empty;
        defer filtered.deinit(arena);
        try filtered.ensureTotalCapacity(arena, hints.len);

        for (hints) |hint| {
            const offset = positionToOffset(state.source, hint.position) orelse {
                try filtered.append(arena, hint);
                continue;
            };

            if (offsetInAnyRange(offset, state.zx_block_ranges)) continue;
            try filtered.append(arena, hint);
        }

        return try filtered.toOwnedSlice(arena);
    }

    fn publishZxDiagnostics(handler: *Handler, uri: []const u8, diag_list: zx.Validate.DiagnosticList) !void {
        var aa = std.heap.ArenaAllocator.init(handler.allocator);
        defer aa.deinit();
        const arena = aa.allocator();

        const lsp_diags = try arena.alloc(lsp.types.flat.Diagnostic, diag_list.items.len);
        for (diag_list.items, 0..) |d, i| {
            lsp_diags[i] = .{
                .range = .{
                    .start = .{ .line = d.start_line, .character = d.start_column },
                    .end = .{ .line = d.end_line, .character = d.end_column },
                },
                .severity = switch (d.severity) {
                    .err => .Error,
                    .warning => .Warning,
                },
                .source = "zx",
                .message = d.message,
            };
        }

        handler.transport.writeNotification(
            handler.io,
            arena,
            "textDocument/publishDiagnostics",
            lsp.types.flat.PublishDiagnosticsParams,
            .{ .uri = uri, .diagnostics = lsp_diags },
            .{ .emit_null_optional_fields = false },
        ) catch |err| {
            std.log.err("Failed to write publishDiagnostics: {}", .{err});
        };
    }

    /// Remap a TextDocumentPositionParams URI for .zx files before forwarding to ZLS.
    fn remapUri(handler: *Handler, comptime T: type, params: T) T {
        if (!isZxUri(params.textDocument.uri)) return params;
        var new_params = params;
        new_params.textDocument = .{ .uri = handler.getZlsUri(params.textDocument.uri) };
        return new_params;
    }

    // -- Lifecycle handlers --

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#initialize
    pub fn initialize(
        handler: *Handler,
        arena: std.mem.Allocator,
        request: lsp.types.flat.InitializeParams,
    ) lsp.types.flat.InitializeResult {
        const client_encoding = choosePositionEncodingKind(request);
        var zls_request = request;
        if (zls_request.capabilities.textDocument) |*text_document| {
            text_document.publishDiagnostics = null;
        }
        if (zls_request.capabilities.general) |*general| {
            general.positionEncodings = &.{client_encoding};
        }

        var result = handler.zls.sendRequestSync(arena, "initialize", zls_request) catch |err| {
            std.log.err("zls initialize failed: {}", .{err});
            return .{
                .serverInfo = .{ .name = "zxls", .version = zx.info.version },
                .capabilities = .{},
            };
        };

        result.capabilities.positionEncoding = client_encoding;
        handler.offset_encoding = toOffsetEncoding(client_encoding);
        return result;
    }

    fn choosePositionEncodingKind(request: lsp.types.flat.InitializeParams) lsp.types.flat.PositionEncodingKind {
        if (request.capabilities.general) |general| {
            if (general.positionEncodings) |encodings| {
                for (encodings) |encoding| {
                    if (encoding == .@"utf-16") return .@"utf-16";
                }
                for (encodings) |encoding| {
                    if (encoding == .@"utf-8") return .@"utf-8";
                }
                for (encodings) |encoding| {
                    switch (encoding) {
                        .@"utf-32" => return .@"utf-32",
                        .custom_value => return .@"utf-16",
                        else => {},
                    }
                }
            }
        }

        return .@"utf-16";
    }

    fn toOffsetEncoding(encoding: lsp.types.flat.PositionEncodingKind) lsp.offsets.Encoding {
        return switch (encoding) {
            .@"utf-8" => .@"utf-8",
            .@"utf-16" => .@"utf-16",
            .@"utf-32" => .@"utf-32",
            .custom_value => .@"utf-16",
        };
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#initialized
    pub fn initialized(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.flat.InitializedParams,
    ) void {
        handler.zls.sendNotificationSync(arena, "initialized", params) catch {};
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#shutdown
    pub fn shutdown(
        handler: *Handler,
        arena: std.mem.Allocator,
        _: void,
    ) ?void {
        return handler.zls.sendRequestSync(arena, "shutdown", {}) catch null;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#exit
    pub fn exit(
        handler: *Handler,
        arena: std.mem.Allocator,
        _: void,
    ) void {
        handler.zls.sendNotificationSync(arena, "exit", {}) catch {};
    }

    // -- Document sync: forward .zx documents to ZLS under their real .zx URI --

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_didOpen
    pub fn @"textDocument/didOpen"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.flat.DidOpenTextDocumentParams,
    ) !void {
        if (isZxUri(params.textDocument.uri)) {
            handler.storeAndDiagnose(params.textDocument.uri, params.textDocument.text);
            const zig_uri = handler.getZlsUri(params.textDocument.uri);

            handler.openZxImportsInZls(arena, params.textDocument.uri, params.textDocument.text);

            handler.zls.sendNotificationSync(arena, "textDocument/didOpen", .{
                .textDocument = .{
                    .uri = zig_uri,
                    .languageId = .{ .custom_value = "zig" },
                    .version = params.textDocument.version,
                    .text = params.textDocument.text,
                },
            }) catch {};
            return;
        }
        handler.zls.sendNotificationSync(arena, "textDocument/didOpen", params) catch {};
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_didChange
    pub fn @"textDocument/didChange"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.flat.DidChangeTextDocumentParams,
    ) !void {
        if (isZxUri(params.textDocument.uri)) {
            // Build full text by applying incremental changes to stored source.
            const current_source = if (handler.zx_files.get(params.textDocument.uri)) |state|
                state.source
            else
                "";

            var full_text: []const u8 = current_source;
            var needs_free = false;
            defer if (needs_free) handler.allocator.free(full_text);

            for (params.contentChanges) |change| {
                switch (change) {
                    .text_document_content_change_whole_document => |full| {
                        if (needs_free) handler.allocator.free(full_text);
                        full_text = full.text;
                        needs_free = false;
                    },
                    .text_document_content_change_partial => |inc| {
                        const new_text = applyIncrementalChange(handler.allocator, full_text, inc.range, inc.text) catch {
                            continue;
                        };
                        if (needs_free) handler.allocator.free(full_text);
                        full_text = new_text;
                        needs_free = true;
                    },
                }
            }

            handler.storeAndDiagnose(params.textDocument.uri, full_text);

            handler.openZxImportsInZls(arena, params.textDocument.uri, full_text);

            const zig_uri = handler.getZlsUri(params.textDocument.uri);
            handler.zls.sendNotificationSync(arena, "textDocument/didChange", .{
                .textDocument = .{
                    .uri = zig_uri,
                    .version = params.textDocument.version,
                },
                .contentChanges = &.{.{ .text_document_content_change_whole_document = .{ .text = full_text } }},
            }) catch {};
            return;
        }
        handler.zls.sendNotificationSync(arena, "textDocument/didChange", params) catch {};
    }

    /// Apply an incremental text change (range + replacement text) to source.
    fn applyIncrementalChange(
        allocator: std.mem.Allocator,
        source: []const u8,
        range: lsp.types.flat.Range,
        new_text: []const u8,
    ) ![]const u8 {
        const start_offset = positionToOffset(source, range.start) orelse return error.InvalidRange;
        const end_offset = positionToOffset(source, range.end) orelse return error.InvalidRange;

        const new_len = start_offset + new_text.len + (source.len - end_offset);
        const result = try allocator.alloc(u8, new_len);
        @memcpy(result[0..start_offset], source[0..start_offset]);
        @memcpy(result[start_offset..][0..new_text.len], new_text);
        @memcpy(result[start_offset + new_text.len ..], source[end_offset..]);
        return result;
    }

    /// Convert an LSP Position (line/character) to a byte offset in the source.
    fn positionToOffset(source: []const u8, pos: lsp.types.flat.Position) ?usize {
        var line: u32 = 0;
        var i: usize = 0;
        while (line < pos.line and i < source.len) {
            if (source[i] == '\n') line += 1;
            i += 1;
        }
        if (line != pos.line) return null;
        // pos.character is in UTF-16 code units; for ASCII this equals byte offset
        const offset = i + pos.character;
        if (offset > source.len) return null;
        return offset;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_didSave
    pub fn @"textDocument/didSave"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.flat.DidSaveTextDocumentParams,
    ) !void {
        if (isZxUri(params.textDocument.uri)) {
            handler.zls.sendNotificationSync(arena, "textDocument/didSave", .{
                .textDocument = .{ .uri = handler.getZlsUri(params.textDocument.uri) },
                .text = params.text,
            }) catch {};
            return;
        }
        handler.zls.sendNotificationSync(arena, "textDocument/didSave", params) catch {};
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_didClose
    pub fn @"textDocument/didClose"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.flat.DidCloseTextDocumentParams,
    ) !void {
        if (isZxUri(params.textDocument.uri)) {
            // Clear diagnostics for the closed file
            handler.transport.writeNotification(
                handler.io,
                arena,
                "textDocument/publishDiagnostics",
                lsp.types.flat.PublishDiagnosticsParams,
                .{ .uri = params.textDocument.uri, .diagnostics = &.{} },
                .{ .emit_null_optional_fields = false },
            ) catch {};

            if (handler.zx_files.fetchRemove(params.textDocument.uri)) |old| {
                const zig_uri = old.value.zig_uri;
                handler.zls.sendNotificationSync(arena, "textDocument/didClose", .{
                    .textDocument = .{ .uri = zig_uri },
                }) catch {};
                handler.allocator.free(old.key);
                var state = old.value;
                state.deinit(handler.allocator);
                return;
            }
        }
        handler.zls.sendNotificationSync(arena, "textDocument/didClose", params) catch {};
    }

    // -- Request handlers: forward to ZLS with URI remapping only (no position remapping) --

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_hover
    pub fn @"textDocument/hover"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.flat.HoverParams,
    ) ?lsp.types.flat.Hover {
        const mapped = handler.remapUri(lsp.types.flat.HoverParams, params);
        return handler.zls.sendRequestSync(arena, "textDocument/hover", mapped) catch null;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_completion
    pub fn @"textDocument/completion"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.flat.CompletionParams,
    ) error{OutOfMemory}!lsp.ResultType("textDocument/completion") {
        const mapped = handler.remapUri(lsp.types.flat.CompletionParams, params);
        return handler.zls.sendRequestSync(arena, "textDocument/completion", mapped) catch null;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_signatureHelp
    pub fn @"textDocument/signatureHelp"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.flat.SignatureHelpParams,
    ) error{OutOfMemory}!?lsp.types.flat.SignatureHelp {
        const mapped = handler.remapUri(lsp.types.flat.SignatureHelpParams, params);
        return handler.zls.sendRequestSync(arena, "textDocument/signatureHelp", mapped) catch null;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_definition
    pub fn @"textDocument/definition"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.flat.DefinitionParams,
    ) error{OutOfMemory}!lsp.ResultType("textDocument/definition") {
        const mapped = handler.remapUri(lsp.types.flat.DefinitionParams, params);
        const result = handler.zls.sendRequestSync(arena, "textDocument/definition", mapped) catch null;
        return handler.remapResponseUris(result);
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_typeDefinition
    pub fn @"textDocument/typeDefinition"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.flat.TypeDefinitionParams,
    ) error{OutOfMemory}!lsp.ResultType("textDocument/typeDefinition") {
        const mapped = handler.remapUri(lsp.types.flat.TypeDefinitionParams, params);
        const result = handler.zls.sendRequestSync(arena, "textDocument/typeDefinition", mapped) catch null;
        return handler.remapResponseUris(result);
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_implementation
    pub fn @"textDocument/implementation"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.flat.ImplementationParams,
    ) error{OutOfMemory}!lsp.ResultType("textDocument/implementation") {
        const mapped = handler.remapUri(lsp.types.flat.ImplementationParams, params);
        const result = handler.zls.sendRequestSync(arena, "textDocument/implementation", mapped) catch null;
        return handler.remapResponseUris(result);
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_declaration
    pub fn @"textDocument/declaration"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.flat.DeclarationParams,
    ) error{OutOfMemory}!lsp.ResultType("textDocument/declaration") {
        const mapped = handler.remapUri(lsp.types.flat.DeclarationParams, params);
        const result = handler.zls.sendRequestSync(arena, "textDocument/declaration", mapped) catch null;
        return handler.remapResponseUris(result);
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_prepareRename
    pub fn @"textDocument/prepareRename"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.flat.PrepareRenameParams,
    ) ?lsp.types.flat.PrepareRenameResult {
        const mapped = handler.remapUri(lsp.types.flat.PrepareRenameParams, params);
        return handler.zls.sendRequestSync(arena, "textDocument/prepareRename", mapped) catch null;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_rename
    pub fn @"textDocument/rename"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.flat.RenameParams,
    ) error{OutOfMemory}!?lsp.types.flat.WorkspaceEdit {
        const mapped = handler.remapUri(lsp.types.flat.RenameParams, params);
        const result = handler.zls.sendRequestSync(arena, "textDocument/rename", mapped) catch null;
        return handler.remapResponseUris(result);
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_references
    pub fn @"textDocument/references"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.flat.ReferenceParams,
    ) error{OutOfMemory}!?[]const lsp.types.flat.Location {
        const mapped = handler.remapUri(lsp.types.flat.ReferenceParams, params);
        const result = handler.zls.sendRequestSync(arena, "textDocument/references", mapped) catch null;
        return handler.remapResponseUris(result);
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_documentHighlight
    pub fn @"textDocument/documentHighlight"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.flat.DocumentHighlightParams,
    ) error{OutOfMemory}!?[]const lsp.types.flat.DocumentHighlight {
        const mapped = handler.remapUri(lsp.types.flat.DocumentHighlightParams, params);
        return handler.zls.sendRequestSync(arena, "textDocument/documentHighlight", mapped) catch null;
    }

    // -- Document-wide handlers --

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_willSaveWaitUntil
    pub fn @"textDocument/willSaveWaitUntil"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.flat.WillSaveTextDocumentParams,
    ) error{OutOfMemory}!?[]const lsp.types.flat.TextEdit {
        return handler.zls.sendRequestSync(arena, "textDocument/willSaveWaitUntil", params) catch null;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_semanticTokens_full
    pub fn @"textDocument/semanticTokens/full"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.flat.SemanticTokensParams,
    ) error{OutOfMemory}!?lsp.types.flat.SemanticTokens {
        if (isZxUri(params.textDocument.uri)) {
            var new_params = params;
            new_params.textDocument = .{ .uri = handler.getZlsUri(params.textDocument.uri) };
            return handler.zls.sendRequestSync(arena, "textDocument/semanticTokens/full", new_params) catch null;
        }
        return handler.zls.sendRequestSync(arena, "textDocument/semanticTokens/full", params) catch null;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_semanticTokens_range
    pub fn @"textDocument/semanticTokens/range"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.flat.SemanticTokensRangeParams,
    ) error{OutOfMemory}!?lsp.types.flat.SemanticTokens {
        return handler.zls.sendRequestSync(arena, "textDocument/semanticTokens/range", params) catch null;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_inlayHint
    pub fn @"textDocument/inlayHint"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.flat.InlayHintParams,
    ) error{OutOfMemory}!?[]const lsp.types.flat.InlayHint {
        if (isZxUri(params.textDocument.uri)) {
            var new_params = params;
            new_params.textDocument = .{ .uri = handler.getZlsUri(params.textDocument.uri) };
            const hints = handler.zls.sendRequestSync(arena, "textDocument/inlayHint", new_params) catch null;
            if (hints) |zls_hints| {
                if (handler.zx_files.get(params.textDocument.uri)) |state| {
                    return try filterInlayHintsForZxBlocks(arena, zls_hints, &state);
                }
            }
            return hints;
        }
        return handler.zls.sendRequestSync(arena, "textDocument/inlayHint", params) catch null;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_documentSymbol
    pub fn @"textDocument/documentSymbol"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.flat.DocumentSymbolParams,
    ) error{OutOfMemory}!lsp.ResultType("textDocument/documentSymbol") {
        if (isZxUri(params.textDocument.uri)) {
            var new_params = params;
            new_params.textDocument = .{ .uri = handler.getZlsUri(params.textDocument.uri) };
            return handler.zls.sendRequestSync(arena, "textDocument/documentSymbol", new_params) catch null;
        }
        return handler.zls.sendRequestSync(arena, "textDocument/documentSymbol", params) catch null;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_formatting
    pub fn @"textDocument/formatting"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.flat.DocumentFormattingParams,
    ) error{OutOfMemory}!?[]const lsp.types.flat.TextEdit {
        if (isZxUri(params.textDocument.uri)) {
            if (handler.zx_files.get(params.textDocument.uri)) |state| {
                const source_z = try handler.allocator.dupeZ(u8, state.source);
                defer handler.allocator.free(source_z);

                var format_result = zx.Ast.fmt(handler.allocator, source_z) catch |err| {
                    std.log.err("zx.Ast.fmt failed for {s}: {s}", .{ params.textDocument.uri, @errorName(err) });
                    return null;
                };
                defer format_result.deinit(handler.allocator);

                const formatted = format_result.source orelse return null;
                if (std.mem.eql(u8, formatted, state.source)) {
                    return null;
                }

                const edits = try arena.alloc(lsp.types.flat.TextEdit, 1);
                edits[0] = .{
                    .range = .{
                        .start = .{ .line = 0, .character = 0 },
                        .end = .{ .line = std.math.maxInt(u32), .character = std.math.maxInt(u32) },
                    },
                    .newText = try arena.dupe(u8, formatted),
                };
                return edits;
            }
        }
        return handler.zls.sendRequestSync(arena, "textDocument/formatting", params) catch null;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_codeAction
    pub fn @"textDocument/codeAction"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.flat.CodeActionParams,
    ) error{OutOfMemory}!lsp.ResultType("textDocument/codeAction") {
        if (isZxUri(params.textDocument.uri)) {
            var new_params = params;
            new_params.textDocument = .{ .uri = handler.getZlsUri(params.textDocument.uri) };
            return handler.zls.sendRequestSync(arena, "textDocument/codeAction", new_params) catch null;
        }
        return handler.zls.sendRequestSync(arena, "textDocument/codeAction", params) catch null;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_foldingRange
    pub fn @"textDocument/foldingRange"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.flat.FoldingRangeParams,
    ) error{OutOfMemory}!?[]const lsp.types.flat.FoldingRange {
        if (isZxUri(params.textDocument.uri)) {
            var new_params = params;
            new_params.textDocument = .{ .uri = handler.getZlsUri(params.textDocument.uri) };
            return handler.zls.sendRequestSync(arena, "textDocument/foldingRange", new_params) catch null;
        }
        return handler.zls.sendRequestSync(arena, "textDocument/foldingRange", params) catch null;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_selectionRange
    pub fn @"textDocument/selectionRange"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.flat.SelectionRangeParams,
    ) error{OutOfMemory}!?[]const lsp.types.flat.SelectionRange {
        return handler.zls.sendRequestSync(arena, "textDocument/selectionRange", params) catch null;
    }

    // -- Workspace handlers --

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#workspace_didChangeWatchedFiles
    pub fn @"workspace/didChangeWatchedFiles"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.flat.DidChangeWatchedFilesParams,
    ) !void {
        handler.zls.sendNotificationSync(arena, "workspace/didChangeWatchedFiles", params) catch {};
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#workspace_didChangeWorkspaceFolders
    pub fn @"workspace/didChangeWorkspaceFolders"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.flat.DidChangeWorkspaceFoldersParams,
    ) !void {
        handler.zls.sendNotificationSync(arena, "workspace/didChangeWorkspaceFolders", params) catch {};
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#workspace_didChangeConfiguration
    pub fn @"workspace/didChangeConfiguration"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.flat.DidChangeConfigurationParams,
    ) !void {
        handler.zls.sendNotificationSync(arena, "workspace/didChangeConfiguration", params) catch {};
    }

    /// We received a response message from the client/editor.
    /// Forward responses to ZLS so it can handle workspace/configuration
    /// responses and other client-to-server responses.
    pub fn onResponse(
        handler: *Handler,
        arena: std.mem.Allocator,
        response: lsp.JsonRPCMessage.Response,
    ) void {
        const json_message = std.json.Stringify.valueAlloc(
            arena,
            lsp.JsonRPCMessage{ .response = response },
            .{ .emit_null_optional_fields = false },
        ) catch |err| {
            std.log.err("zls onResponse stringify failed: {}", .{err});
            return;
        };
        const reply = handler.zls.sendJsonMessageSync(json_message) catch |err| {
            std.log.err("zls sendJsonMessageSync failed: {}", .{err});
            return;
        };
        if (reply) |r| handler.zls.allocator.free(r);
    }
};
