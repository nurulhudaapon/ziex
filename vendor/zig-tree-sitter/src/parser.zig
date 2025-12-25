const build = @import("build");
const std = @import("std");

const InputEdit = @import("tree.zig").InputEdit;
const Language = @import("language.zig").Language;
const Node = @import("node.zig").Node;
const Point = @import("point.zig").Point;
const Range = @import("point.zig").Range;
const Tree = @import("tree.zig").Tree;
const WasmStore = @import("wasm.zig").WasmStore;

/// A struct that specifies how to read input text.
pub const Input = extern struct {
    /// The encoding of source code.
    pub const Encoding = enum(c_uint) {
        utf8,
        utf16le,
        utf16be,
        custom,
    };

    /// An arbitrary pointer that will be passed
    /// to each invocation of the `read` method.
    payload: ?*anyopaque,

    /// A function to retrieve a chunk of text at a given byte offset
    /// and (row, column) position. The function should return a pointer
    /// to the text and write its length to the `bytes_read` pointer.
    /// The parser does not take ownership of this buffer, it just borrows
    /// it until it has finished reading it. The function should write a `0`
    /// value to the `bytes_read` pointer to indicate the end of the document.
    read: *const fn (
        payload: ?*anyopaque,
        byte_index: u32,
        position: Point,
        bytes_read: *u32,
    ) callconv(.c) [*c]const u8,

    /// An indication of how the text is encoded.
    encoding: Input.Encoding = .utf8,

    /// This function reads one code point from the given string, returning
    /// the number of bytes consumed. It should write the code point to
    /// the `code_point` pointer, or write `-1` if the input is invalid.
    decode: ?*const fn (
        string: [*c]const u8,
        length: u32,
        code_point: *i32,
    ) callconv(.c) u32 = null,
};

/// A wrapper around a function that logs parsing results.
pub const Logger = extern struct {
    /// The type of a log message.
    pub const LogType = enum(c_uint) {
        parse,
        lex,
    };

    /// The payload of the function.
    payload: ?*anyopaque = null,

    /// The callback function.
    log: ?*const fn (
        payload: ?*anyopaque,
        log_type: LogType,
        buffer: [*:0]const u8,
    ) callconv(.c) void = null,
};

/// A stateful object that is used to produce
/// a syntax tree based on some source code.
pub const Parser = opaque {
    /// Create a new parser.
    pub fn create() *Parser {
        return ts_parser_new();
    }

    /// Destroy the parser, freeing all of the memory that it used.
    pub fn destroy(self: *Parser) void {
        ts_parser_delete(self);
    }

    /// Get the parser's current language.
    pub fn getLanguage(self: *const Parser) ?*const Language {
        return ts_parser_language(self);
    }

    /// Set the language that the parser should use for parsing.
    ///
    /// Returns an error if the language was not successfully assigned.
    /// The error means that the language was generated with an incompatible
    /// version of the Tree-sitter CLI, or if it was loaded from Wasm and the
    /// parser lacks a Wasm store.
    pub fn setLanguage(self: *Parser, language: ?*const Language) error{IncompatibleLanguage}!void {
        if (!ts_parser_set_language(self, language)) {
            return error.IncompatibleLanguage;
        }
    }

    /// Get the parser's current logger.
    pub fn getLogger(self: *const Parser) Logger {
        return ts_parser_logger(self);
    }

    /// Set the logging callback that the parser should use during parsing.
    ///
    /// Example:
    ///
    /// ```zig
    /// fn scopedLogger(_: ?*anyopaque, log_type: LogType, buffer: [*:0]const u8) callconv(.c) void {
    ///     const scope = switch (log_type) {
    ///         .parse => std.log.scoped(.PARSE),
    ///         .lex => std.log.scoped(.LEX),
    ///     };
    ///     scope.debug("{s}", .{ std.mem.span(buffer) });
    /// }
    ///
    /// parser.setLogger(.{ .log = &scopedLogger });
    /// ```
    pub fn setLogger(self: *Parser, logger: Logger) void {
        return ts_parser_set_logger(self, logger);
    }

    /// Get the ranges of text that the parser will include when parsing.
    pub fn getIncludedRanges(self: *const Parser) []const Range {
        var count: u32 = 0;
        const ranges = ts_parser_included_ranges(self, &count);
        return ranges[0..count];
    }

    /// Set the ranges of text that the parser should include when parsing.
    ///
    /// By default, the parser will always include entire documents.
    /// This method allows you to parse only a *portion* of a document
    /// but still return a syntax tree whose ranges match up with the
    /// document as a whole. You can also pass multiple disjoint ranges.
    ///
    /// If `ranges` is `null` or empty, the entire document will be parsed.
    /// Otherwise, the given ranges must be ordered from earliest
    /// to latest in the document, and they must not overlap. That is, the following
    /// must hold for all `i` < `length - 1`:
    /// ```text
    ///     ranges[i].end_byte <= ranges[i + 1].start_byte
    /// ```
    /// If this requirement is not satisfied, the method will return an
    /// `IncludedRangesError` error.
    pub fn setIncludedRanges(self: *Parser, ranges: ?[]const Range) error{IncludedRangesError}!void {
        if (ranges) |r| {
            if (!ts_parser_set_included_ranges(self, r.ptr, @intCast(r.len))) {
                return error.IncludedRangesError;
            }
        } else {
            _ = ts_parser_set_included_ranges(self, null, 0);
        }
    }

    /// Use the parser to parse some source code and create a syntax tree.
    ///
    /// If you are parsing this document for the first time, pass `null` for the
    /// `old_tree` parameter. Otherwise, if you have already parsed an earlier
    /// version of this document and the document has since been edited, pass the
    /// previous syntax tree so that the unchanged parts of it can be reused.
    /// This will save time and memory. For this to work correctly, you must have
    /// already edited the old syntax tree using the `Tree.edit()` function in a
    /// way that exactly matches the source code changes.
    ///
    /// This function returns a syntax tree on success, and `null` on failure. There
    /// are four possible reasons for failure:
    /// 1. The parser does not have a language assigned. Check for this using the
    ///    `Parser.getLanguage()` method.
    /// 2. Parsing was cancelled due to the progress callback returning true. This callback
    ///    is passed in `Parser.parseWithOptions()` inside the `Parser.Options` struct.
    pub fn parse(
        self: *Parser,
        input: Input,
        old_tree: ?*const Tree,
    ) ?*Tree {
        return ts_parser_parse(self, old_tree, input);
    }

    /// Use the parser to parse some source code and create a syntax tree, with some options.
    ///
    /// See `Parser.parse()` for more details.
    ///
    /// See `Parser.Options` for more details on the options.
    pub fn parseWithOptions(
        self: *Parser,
        input: Input,
        old_tree: ?*const Tree,
        options: Parser.Options,
    ) ?*Tree {
        return ts_parser_parse_with_options(self, old_tree, input, options);
    }

    /// Use the parser to parse some source code stored in one contiguous buffer.
    /// The first two parameters are the same as in the `Parser.parse()` function
    /// above. The second two parameters indicate the location of the buffer and its
    /// length in bytes.
    pub fn parseString(
        self: *Parser,
        string: []const u8,
        old_tree: ?*const Tree,
    ) ?*Tree {
        return ts_parser_parse_string_encoding(
            self,
            old_tree,
            string.ptr,
            @intCast(string.len),
            .utf8,
        );
    }

    /// Use the parser to parse some source code stored in one contiguous buffer with
    /// a given encoding. The first two parameters work the same as in the
    /// `Parser.parseString()` method above. The final parameter indicates whether
    /// the text is encoded as UTF8, UTF16LE, or UTF16BE. You cannot pass in a custom
    /// encoding here. If you need to use a custom encoding, you should use the
    /// `Parser.parse()` method instead.
    pub fn parseStringEncoding(
        self: *Parser,
        string: []const u8,
        old_tree: ?*const Tree,
        encoding: ?Input.Encoding,
    ) ?*Tree {
        return ts_parser_parse_string_encoding(
            self,
            old_tree,
            string.ptr,
            @intCast(string.len),
            encoding orelse .utf8,
        );
    }

    /// Instruct the parser to start the next parse from the beginning.
    ///
    /// If the parser previously failed because of a progress callback,
    /// then by default, it will resume where it left off on the next call to a
    /// parsing method. If you don't want to resume, and instead intend to use
    /// this parser to parse some other document, you must call this method first.
    pub fn reset(self: *Parser) void {
        ts_parser_reset(self);
    }

    /// Assign the given Wasm store to the parser.
    ///
    /// A parser must have a Wasm store in order to use Wasm languages.
    pub fn setWasmStore(self: *Parser, store: *WasmStore) void {
        if (comptime !build.enable_wasm) @compileError("Wasm is not supported");
        ts_parser_set_wasm_store(self, store);
    }

    /// Remove the parser's current Wasm store, if any, and return it.
    pub fn takeWasmStore(self: *Parser) ?*WasmStore {
        if (comptime !build.enable_wasm) @compileError("Wasm is not supported");
        return ts_parser_take_wasm_store(self);
    }

    /// Set the destination to which the parser should write debugging graphs
    /// during parsing. The graphs are formatted in the DOT language. You may
    /// want to pipe these graphs directly to a `dot(1)` process in order to
    /// generate SVG output.
    ///
    /// Pass `null` into `file` to stop printing debugging graphs.
    ///
    /// Example:
    ///
    /// ```zig
    /// parser.printDotGraphs(std.fs.File.stdout());
    /// ```
    pub fn printDotGraphs(self: *Parser, file: ?std.fs.File) void {
        ts_parser_print_dot_graphs(self, if (file) |f| f.handle else -1);
    }

    /// Format the parser as a string.
    pub fn format(self: Parser, writer: *std.Io.Writer) !void {
        try writer.print("Parser(language={?f})", .{self.getLanguage()});
    }

    /// An object that represents the current state of the parser.
    pub const State = extern struct {
        payload: ?*anyopaque = null,
        /// The byte offset in the document that the parser is currently at.
        current_byte_offset: u32,
        /// Indicates whether the parser has encountered an error during parsing.
        has_error: bool,
    };

    /// An object which contains the parsing options.
    pub const Options = extern struct {
        payload: ?*anyopaque = null,
        /// A callback that receives the parse state during parsing.
        progress_callback: *const fn (state: State) callconv(.c) bool,
    };
};

extern fn ts_parser_new() *Parser;
extern fn ts_parser_delete(self: *Parser) void;
extern fn ts_parser_language(self: *const Parser) ?*const Language;
extern fn ts_parser_set_language(self: *Parser, language: ?*const Language) bool;
extern fn ts_parser_set_included_ranges(self: *Parser, ranges: [*c]const Range, count: u32) bool;
extern fn ts_parser_included_ranges(self: *const Parser, count: *u32) [*c]const Range;
extern fn ts_parser_parse(self: *Parser, old_tree: ?*const Tree, input: Input) ?*Tree;
extern fn ts_parser_parse_with_options(
    self: *Parser,
    old_tree: ?*const Tree,
    input: Input,
    options: Parser.Options,
) ?*Tree;
// extern fn ts_parser_parse_string(self: *Parser, old_tree: ?*const Tree, string: [*c]const u8, length: u32) ?*Tree;
extern fn ts_parser_parse_string_encoding(
    self: *Parser,
    old_tree: ?*const Tree,
    string: [*c]const u8,
    length: u32,
    encoding: Input.Encoding,
) ?*Tree;
extern fn ts_parser_reset(self: *Parser) void;
extern fn ts_parser_set_logger(self: *Parser, logger: Logger) void;
extern fn ts_parser_logger(self: *const Parser) Logger;
extern fn ts_parser_print_dot_graphs(self: *Parser, fd: c_int) void;
extern fn ts_parser_set_wasm_store(parser: *Parser, store: *WasmStore) void;
extern fn ts_parser_take_wasm_store(parser: *Parser) ?*WasmStore;
