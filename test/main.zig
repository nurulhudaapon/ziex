const std = @import("std");

test {
    _ = @import("zx/ast.zig");
    _ = @import("cli/fmt.zig");
    _ = @import("cli/cli.zig");
    _ = @import("core/headers.zig");
    _ = @import("core/request.zig");
    _ = @import("core/response.zig");
    _ = @import("core/common.zig");
    _ = @import("core/routing.zig");
    _ = @import("client/hydration.zig");
}

pub const std_options = std.Options{
    .log_level = .info,
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .zx_transpiler, .level = .info },
    },
};
