//! Ziex - A full-stack web framework for Zig
//! This module provides the core component system, rendering engine, and utilities

const std = @import("std");
const builtin = @import("builtin");
const module_options = @import("zx_module_options");

const element = @import("element.zig");
const plfm = @import("platform.zig");
const prp = @import("props.zig");

const routing = @import("runtime/core/routing.zig");
const app_module = @import("runtime/server/Server.zig");
const opts = @import("options.zig");
const ctxs = @import("contexts.zig");
const reactivity = @import("runtime/client/reactivity.zig");
const app_mod = @import("App.zig");

// -- Core Language --//
pub const Ast = if (!module_options.exclude_core_lang) @import("zx_core_lang").Ast else @compileError("core_lang is excluded. Set exclude-core-lang=false to enable.");
pub const Parse = if (!module_options.exclude_core_lang) @import("zx_core_lang").Parse else @compileError("core_lang is excluded. Set exclude-core-lang=false to enable.");
pub const Validate = if (!module_options.exclude_core_lang) @import("zx_core_lang").Validate else @compileError("core_lang is excluded. Set exclude-core-lang=false to enable.");
pub const sourcemap = if (!module_options.exclude_core_lang) @import("zx_core_lang").sourcemap else @compileError("core_lang is excluded. Set exclude-core-lang=false to enable.");

// -- Core -- //
pub const ElementTag = element.Tag;
pub const Component = @import("Component.zig").Component;
pub const Element = @import("Component.zig").Element;

// Internal - Used by the .zx -> .zig transpiler
pub const x = @import("x.zig");

pub const routes = @import("zx_meta").routes;
pub const components = @import("zx_meta").components.components;
pub const meta = @import("zx_meta").meta;
pub const info = @import("zx_info");

// --- Aliases --- //
pub const Allocator = std.mem.Allocator;
pub const log = std.log;

// TODO: Legacy, should be removed
pub const Server = app_module.Server;
pub const Client = @import("runtime/client/Client.zig");

pub const App = app_mod.App;
pub const AppConfig = app_mod.Config;

// --- Namespaces --- //
pub const client = @import("runtime/client.zig");
pub const server = @import("runtime/server.zig");
pub const util = @import("util.zig");
pub const cache = @import("runtime/core//Cache.zig");

// --- Reactivity --- //
pub const EventHandler = @import("runtime/core/EventHandler.zig");
pub const State = reactivity.State;

// --- Options --- //
pub const PageOptions = opts.PageOptions;
pub const LayoutOptions = opts.LayoutOptions;
pub const NotFoundOptions = opts.NotFoundOptions;
pub const ErrorOptions = opts.ErrorOptions;
pub const RouteOptions = opts.RouteOptions;
pub const ProxyOptions = opts.ProxyOptions;
pub const SocketOptions = routing.SocketOptions;

/// --- Contexts --- //
pub const ProxyContext = ctxs.ProxyContext;
pub const PageContext = routing.PageContext;
pub const LayoutContext = routing.LayoutContext;
pub const NotFoundContext = routing.NotFoundContext;
pub const ErrorContext = routing.ErrorContext;
pub const RouteContext = routing.RouteContext;
pub const SocketContext = routing.SocketContext;
pub const SocketCtx = routing.SocketCtx;
pub const SocketOpenContext = routing.SocketOpenContext;
pub const SocketOpenCtx = routing.SocketOpenCtx;
pub const SocketCloseContext = routing.SocketCloseContext;
pub const SocketCloseCtx = routing.SocketCloseCtx;
pub const SocketMessageType = routing.SocketMessageType;
pub const ComponentCtx = ctxs.ComponentCtx;
pub const ComponentContext = ComponentCtx(void);
pub const StateContext = @import("runtime/core/Event.zig").StateContext;
pub const StateHandle = @import("runtime/core/Event.zig").StateHandle;

pub const BuiltinAttribute = @import("attributes.zig").builtin;
pub const Platform = plfm.Platform;

// --- Routing --- //
pub const Router = @import("runtime/core/Router.zig");

// --- Storage --- //
pub const kv = @import("runtime/core/kv.zig");
pub const db = if (!module_options.exclude_db) @import("db") else @compileError("db is excluded. Set exclude-db=false to enable.");

// --- Net --- //
pub const Headers = @import("runtime/core/Headers.zig");
pub const Fetch = @import("runtime/core/Fetch.zig");
pub const WebSocket = @import("runtime/core/WebSocket.zig");
pub const File = @import("runtime/core/File.zig");
pub const Io = Fetch.Io;
pub const Socket = routing.Socket;
pub const fetch = Fetch.fetch;

// --- Values --- //
pub const allocator = app_mod.allocator;
pub const platform: Platform = plfm.platform;
pub const std_options: std.Options = opts.std_options;

// --- StyleSheet (separate cached module) --- //
pub const style = @import("zx_style");
pub const Style = style.Style;
