/// TypeScript (tsc) build config.
const TypescriptBuildConfig = @This();

const std = @import("std");

/// Path to tsconfig.json. Relative paths inside the project are resolved from its directory.
project: ?std.Build.LazyPath = null,

/// Extra file inputs for rebuild tracking (in addition to the project file).
inputs: []const std.Build.LazyPath = &.{},

/// Emit .d.ts files (`--declaration`)
declaration: ?bool = null,

/// Only emit .d.ts files (`--emitDeclarationOnly`)
emit_declaration_only: ?bool = null,

/// Typecheck only (`--noEmit`)
no_emit: ?bool = null,

/// Extra raw CLI args forwarded to tsc
extra_args: []const []const u8 = &.{},
