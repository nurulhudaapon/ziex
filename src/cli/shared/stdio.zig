const std = @import("std");
const log = std.log.scoped(.cli);

/// Output mode for child process streams
pub const OutputMode = enum {
    /// Discard all output
    discard,
    /// Forward raw bytes directly without processing (transparent passthrough)
    transparent,
    /// Process line by line with optional callbacks
    line_buffered,
    /// Capture first line, print it, then continue in transparent mode
    first_line_then_transparent,
};

/// Output target for forwarding child process output
pub const OutputTarget = union(enum) {
    /// Forward to stderr
    stderr,
    /// Forward to stdout
    stdout,
    /// Forward to a custom file
    file: std.fs.File,
    /// Forward to a custom writer
    writer: *std.Io.Writer,
    /// Discard output
    discard,
};

/// Options for individual stream handling
pub const StreamOptions = struct {
    /// Output mode for this stream
    mode: OutputMode = .transparent,
    /// Where to forward output (only used in transparent mode)
    target: OutputTarget = .stderr,
    /// Exit after reading the first line (only used in line_buffered mode)
    exit_on_line: bool = false,
    /// Print lines as they are read (only used in line_buffered mode)
    print_lines: bool = false,
    /// Callback function called for each line (only used in line_buffered mode)
    /// If provided, the line will be passed to this function for custom processing
    on_line: ?*const fn (line: []const u8, stream_name: []const u8) void = null,
    /// Callback function called for each chunk of bytes (only used in transparent mode)
    /// If provided, bytes will be passed to this function instead of writing to target
    on_bytes: ?*const fn (bytes: []const u8, stream_name: []const u8) void = null,

    /// Initial delay before going to transparent mode
    transparent_delay_ms: u64 = 0,
};

/// Options for capturing child process output
pub const ChildOutputOptions = struct {
    /// Options for stderr stream
    stderr: StreamOptions = .{ .mode = .transparent, .target = .stderr },
    /// Options for stdout stream
    stdout: StreamOptions = .{ .mode = .transparent, .target = .stdout },
    /// Timeout in milliseconds (currently unused, reserved for future use)
    timeout_ms: u64 = 0,

    /// Create options for transparent mode (forward all output as-is)
    pub fn transparent() ChildOutputOptions {
        return .{
            .stderr = .{ .mode = .transparent, .target = .stderr },
            .stdout = .{ .mode = .transparent, .target = .stdout },
        };
    }

    /// Create options for line-buffered mode with printing
    pub fn lineBuffered(print_lines: bool) ChildOutputOptions {
        return .{
            .stderr = .{ .mode = .line_buffered, .print_lines = print_lines },
            .stdout = .{ .mode = .line_buffered, .print_lines = print_lines },
        };
    }

    /// Create options for discarding all output
    pub fn discard() ChildOutputOptions {
        return .{
            .stderr = .{ .mode = .discard },
            .stdout = .{ .mode = .discard },
        };
    }
};

/// Context for reading from a child process stream
const StreamContext = struct {
    file: std.fs.File,
    stream_name: []const u8,
    allocator: std.mem.Allocator,
    options: StreamOptions,
    last_line: ?[]const u8 = null,
    done: std.Thread.Mutex = .{},
    done_flag: bool = false,
    first_line_captured: std.Thread.Mutex = .{},
    first_line_captured_flag: bool = false,
};

/// Output handles for child process streams
pub const ChildOutput = struct {
    stderr: *StreamContext,
    stdout: *StreamContext,
    allocator: std.mem.Allocator,

    /// Check if both streams have finished reading
    pub fn isDone(self: *const ChildOutput) bool {
        self.stderr.done.lock();
        defer self.stderr.done.unlock();
        self.stdout.done.lock();
        defer self.stdout.done.unlock();
        return self.stderr.done_flag and self.stdout.done_flag;
    }

    /// Wait for both streams to finish reading
    pub fn wait(self: *const ChildOutput) void {
        while (!self.isDone()) {
            std.Thread.sleep(10 * std.time.ns_per_ms);
        }
    }

    /// Get the last line read from stderr
    pub fn getLastStderrLine(self: *const ChildOutput) ?[]const u8 {
        return self.stderr.last_line;
    }

    /// Get the last line read from stdout
    pub fn getLastStdoutLine(self: *const ChildOutput) ?[]const u8 {
        return self.stdout.last_line;
    }

    /// Wait for the first line to be captured (for first_line_then_transparent mode)
    pub fn waitForFirstLine(self: *const ChildOutput) void {
        while (true) {
            const stderr_captured = blk: {
                self.stderr.first_line_captured.lock();
                defer self.stderr.first_line_captured.unlock();
                break :blk self.stderr.first_line_captured_flag;
            };

            const stdout_captured = blk: {
                self.stdout.first_line_captured.lock();
                defer self.stdout.first_line_captured.unlock();
                break :blk self.stdout.first_line_captured_flag;
            };

            if (stderr_captured or stdout_captured) break;
            std.Thread.sleep(1 * std.time.ns_per_ms);
        }
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *ChildOutput) void {
        self.allocator.destroy(self.stderr);
        self.allocator.destroy(self.stdout);
    }
};

/// Spawn background threads to capture and optionally forward child process output
/// Returns handles to the stream contexts which can be used to check completion or access last_line
/// The returned ChildOutput must be deinitialized with deinit() when done
pub fn captureChildOutput(
    allocator: std.mem.Allocator,
    child: *std.process.Child,
    options: ChildOutputOptions,
) !ChildOutput {
    // Read from stderr in a background thread
    const stderr_ctx = try allocator.create(StreamContext);
    errdefer allocator.destroy(stderr_ctx);

    if (child.stderr) |stderr_file| {
        stderr_ctx.* = StreamContext{
            .file = stderr_file,
            .stream_name = "stderr",
            .allocator = allocator,
            .options = options.stderr,
        };
        if (options.stderr.mode == .discard) {
            stderr_ctx.done_flag = true;
        } else {
            _ = try std.Thread.spawn(.{}, readChildStream, .{stderr_ctx});
        }
    } else {
        // No stderr pipe - mark as done immediately
        stderr_ctx.* = StreamContext{
            .file = std.fs.File{ .handle = undefined },
            .stream_name = "stderr",
            .allocator = allocator,
            .options = options.stderr,
        };
        stderr_ctx.done_flag = true;
    }

    // Read from stdout in a background thread
    const stdout_ctx = try allocator.create(StreamContext);
    errdefer allocator.destroy(stdout_ctx);

    if (child.stdout) |stdout_file| {
        stdout_ctx.* = StreamContext{
            .file = stdout_file,
            .stream_name = "stdout",
            .allocator = allocator,
            .options = options.stdout,
        };
        if (options.stdout.mode == .discard) {
            stdout_ctx.done_flag = true;
        } else {
            _ = try std.Thread.spawn(.{}, readChildStream, .{stdout_ctx});
        }
    } else {
        // No stdout pipe - mark as done immediately
        stdout_ctx.* = StreamContext{
            .file = std.fs.File{ .handle = undefined },
            .stream_name = "stdout",
            .allocator = allocator,
            .options = options.stdout,
        };
        stdout_ctx.done_flag = true;
    }

    return .{
        .stderr = stderr_ctx,
        .stdout = stdout_ctx,
        .allocator = allocator,
    };
}

fn readChildStream(ctx: *StreamContext) void {
    switch (ctx.options.mode) {
        .discard => {
            // Discard mode - just read and throw away
            var buffer: [4096]u8 = undefined;
            while (true) {
                _ = ctx.file.read(&buffer) catch |err| {
                    if (err == error.BrokenPipe) break;
                    log.debug("Error reading {s}: {any}", .{ ctx.stream_name, err });
                    break;
                };
            }
        },
        .transparent => {
            // Transparent mode: read raw bytes and forward immediately without processing
            var buffer: [4096]u8 = undefined;

            while (true) {
                const bytes_read = ctx.file.read(&buffer) catch |err| {
                    if (err == error.BrokenPipe) {
                        break;
                    } else {
                        log.debug("Error reading {s}: {any}", .{ ctx.stream_name, err });
                        break;
                    }
                };

                if (bytes_read == 0) break;

                const bytes = buffer[0..bytes_read];

                // Use callback if provided, otherwise write to target
                if (ctx.options.on_bytes) |callback| {
                    callback(bytes, ctx.stream_name);
                } else {
                    writeToTarget(ctx.options.target, bytes) catch |err| {
                        log.debug("Error writing {s}: {any}", .{ ctx.stream_name, err });
                        break;
                    };
                }
            }
        },
        .line_buffered => {
            // Line buffered mode: read line by line
            var buffer: [4096]u8 = undefined;
            var streaming_reader = ctx.file.readerStreaming(&buffer);
            const io_reader = &streaming_reader.interface;
            var line_writer = std.Io.Writer.Allocating.init(ctx.allocator);
            defer line_writer.deinit();

            // Continuously read lines and process them
            while (io_reader.streamDelimiter(&line_writer.writer, '\n')) |_| {
                std.Thread.sleep(10 * std.time.ns_per_ms);
                const line = line_writer.written();

                if (line.len > 0) {
                    // Store last line
                    ctx.last_line = ctx.allocator.dupe(u8, line) catch null;

                    // Use callback if provided
                    if (ctx.options.on_line) |callback| {
                        callback(line, ctx.stream_name);
                    } else if (ctx.options.print_lines) {
                        // Default: print to debug output
                        std.debug.print("{s}\n", .{line});
                    }
                }

                line_writer.clearRetainingCapacity();

                if (ctx.options.exit_on_line) break;
            } else |err| {
                // Flush any remaining partial line
                const remaining = line_writer.written();
                if (remaining.len > 0) {
                    ctx.last_line = ctx.allocator.dupe(u8, remaining) catch null;

                    if (ctx.options.on_line) |callback| {
                        callback(remaining, ctx.stream_name);
                    } else if (ctx.options.print_lines) {
                        std.debug.print("{s}\n", .{remaining});
                    }
                }

                if (err == error.EndOfStream) {
                    // Normal end of stream
                } else if (err == error.BrokenPipe) {
                    // Pipe closed, normal for process termination
                } else {
                    log.debug("Error reading {s}: {any}", .{ ctx.stream_name, err });
                }
            }
        },
        .first_line_then_transparent => {
            // First, capture the first line
            var buffer: [4096]u8 = undefined;
            var streaming_reader = ctx.file.readerStreaming(&buffer);
            const io_reader = &streaming_reader.interface;
            var line_writer = std.Io.Writer.Allocating.init(ctx.allocator);
            defer line_writer.deinit();

            // Read first line
            if (io_reader.streamDelimiter(&line_writer.writer, '\n')) |_| {
                const line = line_writer.written();
                if (line.len > 0) {
                    ctx.last_line = ctx.allocator.dupe(u8, line) catch null;
                }
            } else |err| {
                // Handle error or EOF - capture any remaining data
                const remaining = line_writer.written();
                if (remaining.len > 0) {
                    ctx.last_line = ctx.allocator.dupe(u8, remaining) catch null;
                }
                if (err != error.EndOfStream and err != error.BrokenPipe) {
                    log.debug("Error reading first line from {s}: {any}", .{ ctx.stream_name, err });
                }
            }

            // Mark first line as captured
            ctx.first_line_captured.lock();
            ctx.first_line_captured_flag = true;
            ctx.first_line_captured.unlock();

            // Continue in transparent mode - first line already consumed by streamDelimiter
            var transparent_buffer: [4096]u8 = undefined;
            while (true) {
                const bytes_read = ctx.file.read(&transparent_buffer) catch |err| {
                    if (err == error.BrokenPipe) break;
                    log.debug("Error reading {s}: {any}", .{ ctx.stream_name, err });
                    break;
                };

                std.Thread.sleep(ctx.options.transparent_delay_ms * std.time.ns_per_ms);

                if (bytes_read == 0) break;

                const bytes = transparent_buffer[0..bytes_read];

                // Use callback if provided, otherwise write to target
                if (ctx.options.on_bytes) |callback| {
                    callback(bytes, ctx.stream_name);
                } else {
                    writeToTarget(ctx.options.target, bytes) catch |err| {
                        log.debug("Error writing {s}: {any}", .{ ctx.stream_name, err });
                        break;
                    };
                }
            }
        },
    }

    // Mark as done
    ctx.done.lock();
    ctx.done_flag = true;
    ctx.done.unlock();
}

fn writeToTarget(target: OutputTarget, bytes: []const u8) !void {
    switch (target) {
        .stderr => try std.fs.File.stderr().writeAll(bytes),
        .stdout => try std.fs.File.stdout().writeAll(bytes),
        .file => |file| try file.writeAll(bytes),
        .writer => |writer| try writer.writeAll(bytes),
        .discard => {},
    }
}
