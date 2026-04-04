comptime {
    @setEvalBranchQuota(100_000);
}

const std = @import("std");
const builtin = @import("builtin");
const zls = @import("zls");
const lsp = zls.lsp;
const zx = @import("zx");
const sourcemap = zx.sourcemap;

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
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
        const home = std.process.getEnvVarOwned(gpa, "HOME") catch break :blk null;
        const cache_suffix = if (builtin.os.tag == .macos) "Library/Caches/zls" else ".cache/zls";
        break :blk std.fs.path.join(gpa, &.{ home, cache_suffix }) catch null;
    };
    defer if (global_cache_path) |p| gpa.free(p);

    var config = zls.Config{ .global_cache_path = global_cache_path };

    const zls_server = zls.Server.create(.{
        .allocator = gpa,
        .transport = transport,
        .config = &config,
    }) catch unreachable;

    var handler: Handler = .init(gpa, zls_server, transport);
    defer handler.deinit();

    try lsp.basic_server.run(
        gpa,
        transport,
        &handler,
        std.log.err,
    );
}

const ZxFileState = struct {
    decoded_map: sourcemap.DecodedMap,
    zig_uri: []const u8,
    source: []const u8,
    zig_source: []const u8,

    fn deinit(self: *ZxFileState, allocator: std.mem.Allocator) void {
        self.decoded_map.deinit();
        allocator.free(self.zig_uri);
        allocator.free(self.source);
        allocator.free(self.zig_source);
    }
};

pub const Handler = struct {
    allocator: std.mem.Allocator,
    zls: *zls.Server,
    transport: *lsp.Transport,
    offset_encoding: lsp.offsets.Encoding,
    zx_files: std.StringHashMap(ZxFileState),

    fn init(allocator: std.mem.Allocator, zls_server: *zls.Server, transport: *lsp.Transport) Handler {
        return .{
            .allocator = allocator,
            .zls = zls_server,
            .transport = transport,
            .offset_encoding = .@"utf-8",
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
        // Replace .zx suffix with .zig
        const base = zx_uri[0 .. zx_uri.len - 3];
        return std.fmt.allocPrint(allocator, "{s}.zig", .{base});
    }

    /// Transpile .zx source via zx.Ast, store the sourcemap, and return the generated Zig source.
    fn transpileAndStore(handler: *Handler, uri: []const u8, source: []const u8) ![]const u8 {
        const source_z = try handler.allocator.dupeZ(u8, source);
        defer handler.allocator.free(source_z);

        var result = zx.Ast.parse(handler.allocator, source_z, .{ .map = .inlined }) catch |err| {
            std.log.err("zx.Ast.parse failed for {s}: {}", .{ uri, err });
            return error.ParseFailed;
        };
        defer result.deinit(handler.allocator);

        handler.publishZxDiagnostics(uri, result.diagnostics) catch |err| {
            std.log.err("Failed to publish diagnostics for {s}: {}", .{ uri, err });
        };

        if (result.diagnostics.hasErrors() or !std.unicode.utf8ValidateSlice(result.zx_source)) {
            handler.updateStoredSource(uri, source_z);
            return error.HasErrors;
        }

        const sm = result.sourcemap orelse return error.NoSourceMap;
        const decoded = try sm.decode(handler.allocator);

        const zig_uri = try toZigUri(handler.allocator, uri);
        const uri_key = try handler.allocator.dupe(u8, uri);
        const zig_source_owned = try handler.allocator.dupe(u8, result.zx_source);
        errdefer handler.allocator.free(zig_source_owned);

        const source_owned = try handler.allocator.dupe(u8, source_z[0..source_z.len]);
        errdefer handler.allocator.free(source_owned);

        // Clean up old state if present
        if (handler.zx_files.fetchRemove(uri)) |old| {
            handler.allocator.free(old.key);
            var old_state = old.value;
            old_state.deinit(handler.allocator);
        }

        try handler.zx_files.put(uri_key, .{
            .decoded_map = decoded,
            .zig_uri = zig_uri,
            .source = source_owned,
            .zig_source = zig_source_owned,
        });

        return try handler.allocator.dupe(u8, result.zx_source);
    }

    fn updateStoredSource(handler: *Handler, uri: []const u8, source: []const u8) void {
        if (handler.zx_files.getPtr(uri)) |state| {
            const new_source = handler.allocator.dupe(u8, source) catch return;
            handler.allocator.free(state.source);
            state.source = new_source;
        }
    }

    fn publishZxDiagnostics(handler: *Handler, uri: []const u8, diag_list: zx.Validate.DiagnosticList) !void {
        var aa = std.heap.ArenaAllocator.init(handler.allocator);
        defer aa.deinit();
        const arena = aa.allocator();

        const lsp_diags = try arena.alloc(lsp.types.Diagnostic, diag_list.items.len);
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
            arena,
            "textDocument/publishDiagnostics",
            lsp.types.PublishDiagnosticsParams,
            .{ .uri = uri, .diagnostics = lsp_diags },
            .{ .emit_null_optional_fields = false },
        ) catch |err| {
            std.log.err("Failed to write publishDiagnostics: {}", .{err});
        };
    }

    /// Remap a position from source (.zx) to generated (.zig) coordinates.
    fn remapPositionToGenerated(handler: *Handler, uri: []const u8, pos: lsp.types.Position) struct { uri: []const u8, pos: lsp.types.Position } {
        const state = handler.zx_files.get(uri) orelse return .{ .uri = uri, .pos = pos };

        if (state.decoded_map.sourceToGenerated(@intCast(pos.line), @intCast(pos.character))) |m| {
            return .{
                .uri = state.zig_uri,
                .pos = .{ .line = @intCast(m.generated_line), .character = @intCast(m.generated_column) },
            };
        }
        return .{ .uri = state.zig_uri, .pos = pos };
    }

    /// Remap a position from generated (.zig) back to source (.zx) coordinates.
    /// Positions are in byte offsets (utf-8 encoding negotiated at init).
    fn remapPositionToSource(handler: *Handler, uri: []const u8, pos: lsp.types.Position) lsp.types.Position {
        var it = handler.zx_files.iterator();
        while (it.next()) |entry| {
            if (std.mem.eql(u8, entry.value_ptr.zig_uri, uri)) {
                const state = entry.value_ptr;
                if (state.decoded_map.generatedToSource(@intCast(pos.line), @intCast(pos.character))) |m| {
                    return .{ .line = @intCast(m.source_line), .character = @intCast(m.source_column) };
                }
                return pos;
            }
        }
        return pos;
    }

    /// Remap a range from generated (.zig) back to source (.zx) coordinates.
    fn remapRangeToSource(handler: *Handler, uri: []const u8, range: lsp.types.Range) lsp.types.Range {
        return .{
            .start = handler.remapPositionToSource(uri, range.start),
            .end = handler.remapPositionToSource(uri, range.end),
        };
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#initialize
    pub fn initialize(
        handler: *Handler,
        arena: std.mem.Allocator,
        request: lsp.types.InitializeParams,
    ) lsp.types.InitializeResult {
        var result = handler.zls.sendRequestSync(arena, "initialize", request) catch |err| {
            std.log.err("zls initialize failed: {}", .{err});
            return .{
                .serverInfo = .{ .name = "zxls", .version = "0.1.0" },
                .capabilities = .{},
            };
        };

        const client_supports_utf8 = if (request.capabilities.general) |general|
            if (general.positionEncodings) |encodings| blk: {
                for (encodings) |enc| {
                    if (enc == .@"utf-8") break :blk true;
                }
                break :blk false;
            } else false
        else
            false;

        if (client_supports_utf8) {
            result.capabilities.positionEncoding = .@"utf-8";
            handler.offset_encoding = .@"utf-8";
        } else if (result.capabilities.positionEncoding) |encoding| {
            handler.offset_encoding = switch (encoding) {
                .@"utf-8" => .@"utf-8",
                .@"utf-16" => .@"utf-16",
                .@"utf-32" => .@"utf-32",
                .custom_value => .@"utf-16",
            };
        }
        return result;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#initialized
    pub fn initialized(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.InitializedParams,
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

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_didOpen
    pub fn @"textDocument/didOpen"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.DidOpenTextDocumentParams,
    ) !void {
        if (isZxUri(params.textDocument.uri)) {
            const zig_source = handler.transpileAndStore(params.textDocument.uri, params.textDocument.text) catch {
                // Fallback: send original source to ZLS
                handler.zls.sendNotificationSync(arena, "textDocument/didOpen", params) catch {};
                return;
            };
            defer handler.allocator.free(zig_source);

            const state = handler.zx_files.get(params.textDocument.uri).?;
            handler.zls.sendNotificationSync(arena, "textDocument/didOpen", .{
                .textDocument = .{
                    .uri = state.zig_uri,
                    .languageId = "zig",
                    .version = params.textDocument.version,
                    .text = zig_source,
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
        params: lsp.types.DidChangeTextDocumentParams,
    ) !void {
        if (isZxUri(params.textDocument.uri)) {
            // Build the full text by applying content changes to the stored source.
            const current_source = if (handler.zx_files.get(params.textDocument.uri)) |state|
                state.source
            else
                "";

            var full_text: []const u8 = current_source;
            var needs_free = false;
            defer if (needs_free) handler.allocator.free(full_text);

            for (params.contentChanges) |change| {
                switch (change) {
                    .literal_1 => |full| {
                        if (needs_free) handler.allocator.free(full_text);
                        full_text = full.text;
                        needs_free = false;
                    },
                    .literal_0 => |inc| {
                        const new_text = applyIncrementalChange(handler.allocator, full_text, inc.range, inc.text) catch {
                            continue;
                        };
                        if (needs_free) handler.allocator.free(full_text);
                        full_text = new_text;
                        needs_free = true;
                    },
                }
            }

            const zig_source = handler.transpileAndStore(params.textDocument.uri, full_text) catch {
                handler.zls.sendNotificationSync(arena, "textDocument/didChange", params) catch {};
                return;
            };
            defer handler.allocator.free(zig_source);

            const state = handler.zx_files.get(params.textDocument.uri).?;
            handler.zls.sendNotificationSync(arena, "textDocument/didChange", .{
                .textDocument = .{
                    .uri = state.zig_uri,
                    .version = params.textDocument.version,
                },
                .contentChanges = &.{.{ .literal_1 = .{ .text = zig_source } }},
            }) catch {};
            return;
        }
        handler.zls.sendNotificationSync(arena, "textDocument/didChange", params) catch {};
    }

    /// Apply an incremental text change (range + replacement text) to source.
    fn applyIncrementalChange(
        allocator: std.mem.Allocator,
        source: []const u8,
        range: lsp.types.Range,
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
    fn positionToOffset(source: []const u8, pos: lsp.types.Position) ?usize {
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
        params: lsp.types.DidSaveTextDocumentParams,
    ) !void {
        if (isZxUri(params.textDocument.uri)) {
            if (handler.zx_files.get(params.textDocument.uri)) |state| {
                handler.zls.sendNotificationSync(arena, "textDocument/didSave", .{
                    .textDocument = .{ .uri = state.zig_uri },
                    .text = params.text,
                }) catch {};
                return;
            }
        }
        handler.zls.sendNotificationSync(arena, "textDocument/didSave", params) catch {};
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_didClose
    pub fn @"textDocument/didClose"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.DidCloseTextDocumentParams,
    ) !void {
        if (isZxUri(params.textDocument.uri)) {
            // Clear diagnostics for the closed file
            handler.transport.writeNotification(
                arena,
                "textDocument/publishDiagnostics",
                lsp.types.PublishDiagnosticsParams,
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

    // -- Request handlers with position remapping --

    /// Helper: remap a TextDocumentPositionParams for .zx files before forwarding to ZLS.
    fn remapTextDocPositionParams(handler: *Handler, comptime T: type, params: T) T {
        if (!isZxUri(params.textDocument.uri)) return params;
        const remapped = handler.remapPositionToGenerated(params.textDocument.uri, params.position);
        var new_params = params;
        new_params.textDocument = .{ .uri = remapped.uri };
        new_params.position = remapped.pos;
        return new_params;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_hover
    pub fn @"textDocument/hover"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.HoverParams,
    ) ?lsp.types.Hover {
        const mapped = handler.remapTextDocPositionParams(lsp.types.HoverParams, params);
        var result = handler.zls.sendRequestSync(arena, "textDocument/hover", mapped) catch return null;
        if (result) |*hover| {
            if (hover.range) |range| {
                hover.range = handler.remapRangeToSource(mapped.textDocument.uri, range);
            }
        }
        return result;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_completion
    pub fn @"textDocument/completion"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.CompletionParams,
    ) error{OutOfMemory}!lsp.ResultType("textDocument/completion") {
        const mapped = handler.remapTextDocPositionParams(lsp.types.CompletionParams, params);
        return handler.zls.sendRequestSync(arena, "textDocument/completion", mapped) catch null;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_signatureHelp
    pub fn @"textDocument/signatureHelp"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.SignatureHelpParams,
    ) error{OutOfMemory}!?lsp.types.SignatureHelp {
        const mapped = handler.remapTextDocPositionParams(lsp.types.SignatureHelpParams, params);
        return handler.zls.sendRequestSync(arena, "textDocument/signatureHelp", mapped) catch null;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_definition
    pub fn @"textDocument/definition"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.DefinitionParams,
    ) error{OutOfMemory}!lsp.ResultType("textDocument/definition") {
        const mapped = handler.remapTextDocPositionParams(lsp.types.DefinitionParams, params);
        return handler.zls.sendRequestSync(arena, "textDocument/definition", mapped) catch null;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_typeDefinition
    pub fn @"textDocument/typeDefinition"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.TypeDefinitionParams,
    ) error{OutOfMemory}!lsp.ResultType("textDocument/typeDefinition") {
        const mapped = handler.remapTextDocPositionParams(lsp.types.TypeDefinitionParams, params);
        return handler.zls.sendRequestSync(arena, "textDocument/typeDefinition", mapped) catch null;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_implementation
    pub fn @"textDocument/implementation"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.ImplementationParams,
    ) error{OutOfMemory}!lsp.ResultType("textDocument/implementation") {
        const mapped = handler.remapTextDocPositionParams(lsp.types.ImplementationParams, params);
        return handler.zls.sendRequestSync(arena, "textDocument/implementation", mapped) catch null;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_declaration
    pub fn @"textDocument/declaration"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.DeclarationParams,
    ) error{OutOfMemory}!lsp.ResultType("textDocument/declaration") {
        const mapped = handler.remapTextDocPositionParams(lsp.types.DeclarationParams, params);
        return handler.zls.sendRequestSync(arena, "textDocument/declaration", mapped) catch null;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_prepareRename
    pub fn @"textDocument/prepareRename"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.PrepareRenameParams,
    ) ?lsp.types.PrepareRenameResult {
        const mapped = handler.remapTextDocPositionParams(lsp.types.PrepareRenameParams, params);
        return handler.zls.sendRequestSync(arena, "textDocument/prepareRename", mapped) catch null;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_rename
    pub fn @"textDocument/rename"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.RenameParams,
    ) error{OutOfMemory}!?lsp.types.WorkspaceEdit {
        const mapped = handler.remapTextDocPositionParams(lsp.types.RenameParams, params);
        return handler.zls.sendRequestSync(arena, "textDocument/rename", mapped) catch null;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_references
    pub fn @"textDocument/references"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.ReferenceParams,
    ) error{OutOfMemory}!?[]const lsp.types.Location {
        const mapped = handler.remapTextDocPositionParams(lsp.types.ReferenceParams, params);
        const result = handler.zls.sendRequestSync(arena, "textDocument/references", mapped) catch null;
        return result;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_documentHighlight
    pub fn @"textDocument/documentHighlight"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.DocumentHighlightParams,
    ) error{OutOfMemory}!?[]const lsp.types.DocumentHighlight {
        const mapped = handler.remapTextDocPositionParams(lsp.types.DocumentHighlightParams, params);
        const result = handler.zls.sendRequestSync(arena, "textDocument/documentHighlight", mapped) catch null;
        return result;
    }

    // -- Handlers that operate on the whole document (no position remapping needed on input) --

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_willSaveWaitUntil
    pub fn @"textDocument/willSaveWaitUntil"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.WillSaveTextDocumentParams,
    ) error{OutOfMemory}!?[]const lsp.types.TextEdit {
        const result = handler.zls.sendRequestSync(arena, "textDocument/willSaveWaitUntil", params) catch null;
        return result;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_semanticTokens_full
    pub fn @"textDocument/semanticTokens/full"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.SemanticTokensParams,
    ) error{OutOfMemory}!?lsp.types.SemanticTokens {
        if (isZxUri(params.textDocument.uri)) {
            if (handler.zx_files.get(params.textDocument.uri)) |state| {
                var new_params = params;
                new_params.textDocument = .{ .uri = state.zig_uri };
                return handler.zls.sendRequestSync(arena, "textDocument/semanticTokens/full", new_params) catch null;
            }
        }
        return handler.zls.sendRequestSync(arena, "textDocument/semanticTokens/full", params) catch null;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_semanticTokens_range
    pub fn @"textDocument/semanticTokens/range"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.SemanticTokensRangeParams,
    ) error{OutOfMemory}!?lsp.types.SemanticTokens {
        return handler.zls.sendRequestSync(arena, "textDocument/semanticTokens/range", params) catch null;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_inlayHint
    pub fn @"textDocument/inlayHint"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.InlayHintParams,
    ) error{OutOfMemory}!?[]const lsp.types.InlayHint {
        if (isZxUri(params.textDocument.uri)) {
            if (handler.zx_files.get(params.textDocument.uri)) |state| {
                var new_params = params;
                new_params.textDocument = .{ .uri = state.zig_uri };
                const result = handler.zls.sendRequestSync(arena, "textDocument/inlayHint", new_params) catch null;
                return result;
            }
        }
        const result = handler.zls.sendRequestSync(arena, "textDocument/inlayHint", params) catch null;
        return result;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_documentSymbol
    pub fn @"textDocument/documentSymbol"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.DocumentSymbolParams,
    ) error{OutOfMemory}!lsp.ResultType("textDocument/documentSymbol") {
        if (isZxUri(params.textDocument.uri)) {
            if (handler.zx_files.get(params.textDocument.uri)) |state| {
                var new_params = params;
                new_params.textDocument = .{ .uri = state.zig_uri };
                return handler.zls.sendRequestSync(arena, "textDocument/documentSymbol", new_params) catch null;
            }
        }
        return handler.zls.sendRequestSync(arena, "textDocument/documentSymbol", params) catch null;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_formatting
    pub fn @"textDocument/formatting"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.DocumentFormattingParams,
    ) error{OutOfMemory}!?[]const lsp.types.TextEdit {
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

                const edits = try arena.alloc(lsp.types.TextEdit, 1);
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
        params: lsp.types.CodeActionParams,
    ) error{OutOfMemory}!lsp.ResultType("textDocument/codeAction") {
        if (isZxUri(params.textDocument.uri)) {
            if (handler.zx_files.get(params.textDocument.uri)) |state| {
                var new_params = params;
                new_params.textDocument = .{ .uri = state.zig_uri };
                new_params.range = handler.remapRangeToSource(state.zig_uri, params.range);
                return handler.zls.sendRequestSync(arena, "textDocument/codeAction", new_params) catch null;
            }
        }
        return handler.zls.sendRequestSync(arena, "textDocument/codeAction", params) catch null;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_foldingRange
    pub fn @"textDocument/foldingRange"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.FoldingRangeParams,
    ) error{OutOfMemory}!?[]const lsp.types.FoldingRange {
        if (isZxUri(params.textDocument.uri)) {
            if (handler.zx_files.get(params.textDocument.uri)) |state| {
                var new_params = params;
                new_params.textDocument = .{ .uri = state.zig_uri };
                const result = handler.zls.sendRequestSync(arena, "textDocument/foldingRange", new_params) catch null;
                return result;
            }
        }
        const result = handler.zls.sendRequestSync(arena, "textDocument/foldingRange", params) catch null;
        return result;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_selectionRange
    pub fn @"textDocument/selectionRange"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.SelectionRangeParams,
    ) error{OutOfMemory}!?[]const lsp.types.SelectionRange {
        const result = handler.zls.sendRequestSync(arena, "textDocument/selectionRange", params) catch null;
        return result;
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#workspace_didChangeWatchedFiles
    pub fn @"workspace/didChangeWatchedFiles"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.DidChangeWatchedFilesParams,
    ) !void {
        handler.zls.sendNotificationSync(arena, "workspace/didChangeWatchedFiles", params) catch {};
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#workspace_didChangeWorkspaceFolders
    pub fn @"workspace/didChangeWorkspaceFolders"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.DidChangeWorkspaceFoldersParams,
    ) !void {
        handler.zls.sendNotificationSync(arena, "workspace/didChangeWorkspaceFolders", params) catch {};
    }

    /// https://microsoft.github.io/language-server-protocol/specifications/specification-current/#workspace_didChangeConfiguration
    pub fn @"workspace/didChangeConfiguration"(
        handler: *Handler,
        arena: std.mem.Allocator,
        params: lsp.types.DidChangeConfigurationParams,
    ) !void {
        handler.zls.sendNotificationSync(arena, "workspace/didChangeConfiguration", params) catch {};
    }

    /// We received a response message from the client/editor.
    /// Forward responses to ZLS so it can handle workspace/configuration
    /// responses and other client-to-server responses.
    pub fn onResponse(
        handler: *Handler,
        _: std.mem.Allocator,
        response: lsp.JsonRPCMessage.Response,
    ) void {
        handler.zls.handleResponse(response) catch |err| {
            std.log.err("zls handleResponse failed: {}", .{err});
        };
    }
};
