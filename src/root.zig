//! Ziex - A full-stack web framework for Zig
//! This module provides the core component system, rendering engine, and utilities

const std = @import("std");
const builtin = @import("builtin");

const element = @import("element.zig");
const plfm = @import("platform.zig");
const prp = @import("props.zig");
const z = @import("zx.zig");

const routing = @import("runtime/core/routing.zig");
const app_module = @import("runtime/server/Server.zig");
const opts = @import("options.zig");
const ctxs = @import("contexts.zig");
const reactivity = @import("runtime/client/reactivity.zig");

// -- Core Language --//
pub const Ast = @import("core/Ast.zig");
pub const Parse = @import("core/Parse.zig");
pub const sourcemap = @import("core/sourcemap.zig");

// -- Core -- //
pub const ElementTag = element.Tag;
pub const Component = @import("Component.zig").Component;
pub const Element = @import("Component.zig").Element;
const ZxOptions = z.ZxOptions;
pub const ZxContext = z.ZxContext;

pub const zx = z.x;
pub const lazy = z.lazy;
pub const init = z.init;
pub const allocInit = z.allocInit;

pub const routes = @import("zx_meta").routes;
pub const components = @import("zx_meta").components.components;
pub const meta = @import("zx_meta").meta;
pub const info = @import("zx_info");

// --- Aliases --- //
pub const Allocator = std.mem.Allocator;
pub const log = std.log;

pub const Server = app_module.Server;
pub const Edge = @import("runtime/server/wasm/entrypoint.zig");
pub const Client = @import("runtime/client/Client.zig");

// --- Namespaces --- //
pub const client = @import("runtime/client.zig");
pub const server = @import("runtime/server.zig");
pub const util = @import("util.zig");
pub const cache = @import("runtime/core//Cache.zig");

// --- Reactivity --- //
pub const EventHandler = @import("runtime/core/EventHandler.zig");
pub const State = reactivity.State;

// --- Options --- //
pub const AppOptions = app_module.ServerConfig;
pub const PageOptions = opts.PageOptions;
pub const LayoutOptions = opts.LayoutOptions;
pub const NotFoundOptions = opts.NotFoundOptions;
pub const ErrorOptions = opts.ErrorOptions;
pub const RouteOptions = opts.RouteOptions;
pub const ProxyOptions = opts.ProxyOptions;
pub const SocketOptions = routing.SocketOptions;

/// --- Contexts --- //
pub const ProxyContext = ctxs.ProxyContext;
pub const AppCtx = routing.AppCtx;
pub const PageContext = routing.PageContext;
pub const PageCtx = routing.PageCtx;
pub const LayoutContext = routing.LayoutContext;
pub const LayoutCtx = routing.LayoutCtx;
pub const NotFoundContext = routing.NotFoundContext;
pub const NotFoundCtx = routing.NotFoundCtx;
pub const ErrorContext = routing.ErrorContext;
pub const RouteContext = routing.RouteContext;
pub const RouteCtx = routing.RouteCtx;
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
pub const db = @panic("TODO: Database not implemented yet");

// --- Net --- //
pub const Headers = @import("runtime/core/Headers.zig");
pub const Fetch = @import("runtime/core/Fetch.zig");
pub const WebSocket = @import("runtime/core/WebSocket.zig");
pub const File = @import("runtime/core/File.zig");
pub const Io = Fetch.Io;
pub const Socket = routing.Socket;
pub const fetch = Fetch.fetch;

// --- Values --- //
pub const client_allocator = if (builtin.os.tag == .freestanding) std.heap.wasm_allocator else std.heap.page_allocator;
pub const platform: Platform = plfm.platform;
pub const std_options: std.Options = opts.std_options;

// --- StyleSheet --- //
pub const style = @import("style/root.zig");
pub const Style = style.Style;
