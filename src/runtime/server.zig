const server = @import("server/Server.zig");

pub const Event = @import("server/Event.zig");
pub const Action = @import("server/Action.zig");
pub const db = @import("server/db.zig");

// Legacy --- will be renamed
pub const SerilizableAppMeta = server.SerilizableAppMeta;
pub const ServerMeta = server.ServerMeta;

// Legacy -- may be kept
pub const Request = @import("core/Request.zig");
pub const Response = @import("core/Response.zig");
pub const ServerConfig = server.ServerConfig;
