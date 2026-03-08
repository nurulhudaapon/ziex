//! Ziex - A full-stack web framework for Zig
//! This module provides the core component system, rendering engine, and utilities

const std = @import("std");
const builtin = @import("builtin");

const element = @import("element.zig");
const plfm = @import("platform.zig");
const prp = @import("props.zig");
const z = @import("zx.zig");

const routing = @import("runtime/core/routing.zig");
const hydration = @import("runtime/client/hydration.zig");
const app_module = @import("runtime/server/Server.zig");
const opts = @import("options.zig");
const ctxs = @import("contexts.zig");
const reactivity = @import("runtime/client/reactivity.zig");

pub const devtool = @import("devtool.zig");
pub const cache = @import("runtime/core//Cache.zig");

// -- Core Language --//
pub const Ast = @import("core/Ast.zig");
pub const Parse = @import("core/Parse.zig");

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

pub const Allocator = std.mem.Allocator;
pub const App = app_module.Server(void);
pub const Server = app_module.Server;
pub const Edge = @import("runtime/edge/Edge.zig").Edge;
pub const Client = @import("runtime/client/Client.zig");

pub const prop = prp.prop;
pub const client = @import("runtime/client/window.zig");

// --- Reactivity --- //
pub const Computed = reactivity.Computed;
pub const Effect = reactivity.Effect;
pub const CleanupFn = reactivity.CleanupFn;
pub const EventHandler = reactivity.EventHandler;
pub const signal = reactivity.signal;
pub const effect = reactivity.effect;
pub const effectDeferred = reactivity.effectDeferred;
// TODO: this is currently VDom based re-render, remove this once signal system can trigger complex-re-render
pub const rerender = reactivity.rerender;

// --- Options --- //
pub const PageMethod = opts.PageMethod;
pub const PageOptions = opts.PageOptions;
pub const LayoutOptions = opts.LayoutOptions;
pub const NotFoundOptions = opts.NotFoundOptions;
pub const ErrorOptions = opts.ErrorOptions;
pub const RouteOptions = opts.RouteOptions;
pub const ProxyOptions = opts.ProxyOptions;

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
pub const Socket = routing.Socket;
pub const SocketOptions = routing.SocketOptions;
pub const ComponentCtx = ctxs.ComponentCtx;
pub const ComponentContext = ComponentCtx(void);
pub const EventContext = ctxs.EventContext;
pub const ActionContext = ctxs.ActionContext;

pub const BuiltinAttribute = @import("attributes.zig").builtin;
pub const Platform = plfm.Platform;

// --- Net --- //
pub const Headers = @import("runtime/core/Headers.zig");
pub const Request = @import("runtime/core/Request.zig");
pub const Response = @import("runtime/core/Response.zig");
pub const Fetch = @import("runtime/core/Fetch.zig");
pub const WebSocket = @import("runtime/core/WebSocket.zig");
pub const Io = Fetch.Io;
pub const fetch = Fetch.fetch;

// --- Values --- //
pub const client_allocator = if (builtin.os.tag == .freestanding) std.heap.wasm_allocator else std.heap.page_allocator;
pub const platform: Platform = plfm.platform;
pub const std_options: std.Options = opts.std_options;
