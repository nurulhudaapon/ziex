comptime {
    @setEvalBranchQuota(100_000);
}

const std = @import("std");
const build_options = @import("build_options");
const lsp = @import("lsp");
const Handler = @import("Handler.zig");
const Message = @import("transport/Message.zig");
const CommandContext = @import("../cli/shared/context.zig").CommandContext;

pub fn run(ctx: CommandContext, messages: []const []const u8) !void {
    if (messages.len > 0) {
        try Message.runMessages(messages, ctx.writer);
        return;
    }
    try runStdio(ctx);
}

fn runStdio(ctx: CommandContext) !void {
    const gpa = ctx.allocator;
    const io = ctx.app.io;
    const environ_map = ctx.app.environ_map;

    @setEvalBranchQuota(100_000);

    var read_buffer: [256]u8 = undefined;
    var stdio_transport: lsp.Transport.Stdio = .init(&read_buffer, .stdin(), .stdout());
    const transport: *lsp.Transport = &stdio_transport.transport;

    var handler: Handler = .init(gpa, transport, io);
    defer handler.deinit();

    if (comptime Handler.Zls.enabled) {
        const backing = try Handler.Zls.create(.{
            .allocator = gpa,
            .io = io,
            .transport = transport,
            .environ_map = environ_map,
        });
        handler.setBacking(backing.ptr, backing.vtable);
    }

    lsp.basic_server.run(
        io,
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
