//! Public ZX CLI module (`@import("cli")`).
//! Full CLI entry + command dispatch for the `zx` binary and downstream embeddings.
const impl = @import("cli/main.zig");

pub const main = impl.main;
pub const run = impl.run;
pub const std_options = impl.std_options;
pub const AppContext = impl.AppContext;
pub const CommandContext = impl.CommandContext;
pub const root_command = impl.root_command;
pub const commands = impl.commands;
