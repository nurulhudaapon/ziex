const build = @import("build");
const std = @import("std");

const alloc = @import("alloc.zig");
const Parser = @import("parser.zig").Parser;
const Language = @import("language.zig").Language;

const WasmError = extern struct {
    kind: enum(c_uint) {
        none,
        parse,
        compile,
        instantiate,
        allocate,
    },
    message: [*c]const u8 = undefined,
};

// TODO: delegate to wasmtime Zig bindings when available

/// Wasm compilation environment.
///
/// See [`wasm_engine_t`](https://docs.wasmtime.dev/c-api/structwasm__engine__t.html)
pub const WasmEngine = opaque {
    /// Initialize a new Wasm engine with the specified configuration,
    /// or the default configuration if `null`.
    pub fn init(config: ?*Config) error{AllocateError}!*WasmEngine {
        if (comptime !build.enable_wasm) @compileError("Wasm is not supported");
        const engine = if (config) |c| wasm_engine_new_with_config(c) else wasm_engine_new();
        return engine orelse error.AllocateError;
    }

    /// Deinitialize a Wasm engine.
    pub fn deinit(self: *WasmEngine) void {
        if (comptime !build.enable_wasm) @compileError("Wasm is not supported");
        wasm_engine_delete(self);
    }

    /// Global engine configuration.
    ///
    /// See [`wasmtime/config.h`](https://docs.wasmtime.dev/c-api/config_8h.html)
    pub const Config = opaque {};
};

/// A stateful object that stores Wasm languages.
pub const WasmStore = opaque {
    /// Create a Wasm store.
    pub fn create(allocator: std.mem.Allocator, engine: *WasmEngine, error_message: *[]u8) Error!*WasmStore {
        if (comptime !build.enable_wasm) @compileError("Wasm is not supported");
        var wasm_error: WasmError = .{ .kind = .none };
        const store = ts_wasm_store_new(engine, &wasm_error);
        if (wasm_error.kind == .none) return store.?;

        const message: []const u8 = std.mem.span(wasm_error.message);
        error_message.* = allocator.dupe(u8, message) catch return error.AllocateError;
        alloc.free_fn()(@ptrCast(@constCast(wasm_error.message)));
        return switch (wasm_error.kind) {
            .parse => error.ParseError,
            .compile => error.CompileError,
            .instantiate => error.InstantiateError,
            .allocate => error.AllocateError,
            .none => unreachable,
        };
    }

    /// Free the memory associated with the given Wasm store.
    pub inline fn destroy(self: *WasmStore) void {
        if (comptime !build.enable_wasm) @compileError("Wasm is not supported");
        ts_wasm_store_delete(self);
    }

    /// Load a language from a buffer of Wasm.
    ///
    /// The resulting language behaves like any other Tree-sitter
    /// language, except that in order to use it with a language,
    /// that parser must have a Wasm store.
    ///
    /// Note that the language can be used with any Wasm store,
    /// it doesn't need to be the same store that was used to originally load it.
    pub fn loadLanguage(
        self: *WasmStore,
        allocator: std.mem.Allocator,
        name: [:0]const u8,
        wasm: []const u8,
        error_message: *[]u8,
    ) Error!*const Language {
        if (comptime !build.enable_wasm) @compileError("Wasm is not supported");
        var wasm_error: WasmError = .{ .kind = .none };
        const language = ts_wasm_store_load_language(self, name.ptr, wasm.ptr, @intCast(wasm.len), &wasm_error);
        if (wasm_error.kind == .none) return language.?;

        const message: []const u8 = std.mem.span(wasm_error.message);
        error_message.* = allocator.dupe(u8, message) catch return error.AllocateError;
        alloc.free_fn()(@ptrCast(@constCast(wasm_error.message)));
        return switch (wasm_error.kind) {
            .parse => error.ParseError,
            .compile => error.CompileError,
            .instantiate => error.InstantiateError,
            .allocate => error.AllocateError,
            .none => unreachable,
        };
    }

    /// Get the number of languages instantiated in this Wasm store.
    pub inline fn languageCount(self: *WasmStore) usize {
        if (comptime !build.enable_wasm) @compileError("Wasm is not supported");
        return ts_wasm_store_language_count(self);
    }

    /// The kind of error that occurred in Wasm.
    pub const Error = error{
        ParseError,
        CompileError,
        InstantiateError,
        AllocateError,
    };
};

extern fn ts_wasm_store_new(engine: *WasmEngine, wasm_error: *WasmError) ?*WasmStore;
extern fn ts_wasm_store_delete(store: *WasmStore) void;
extern fn ts_wasm_store_load_language(
    store: *WasmStore,
    name: [*c]const u8,
    wasm: [*c]const u8,
    wasm_len: u32,
    wasm_error: *WasmError,
) ?*const Language;
extern fn ts_wasm_store_language_count(store: *const WasmStore) usize;

// from wasmtime
extern fn wasm_engine_new_with_config(config: ?*WasmEngine.Config) ?*WasmEngine;
extern fn wasm_engine_new() ?*WasmEngine;
extern fn wasm_engine_delete(engine: ?*WasmEngine) void;
