//! ZX - A Zig library for building web applications with JSX-like syntax.
//! This module provides the core component system, rendering engine, and utilities
//! for creating type-safe, high-performance web applications with server-side rendering.
const std = @import("std");
pub const devtool = @import("devtool.zig");
pub const Ast = @import("core/Ast.zig");
pub const Parse = @import("core/Parse.zig");
/// Global cache for components and pages
pub const cache = @import("runtime/core//Cache.zig");

// HTML Tags
pub const ElementTag = enum {
    aside,
    fragment,
    iframe,
    slot,
    img,
    html,
    base,
    head,
    link,
    meta,
    script,
    style,
    title,
    address,
    article,
    body,
    h1,
    h6,
    footer,
    header,
    h2,
    h3,
    h4,
    h5,
    hgroup,
    nav,
    section,
    dd,
    dl,
    dt,
    div,
    figcaption,
    figure,
    hr,
    li,
    ol,
    ul,
    menu,
    main,
    p,
    picture,
    pre,
    a,
    abbr,
    b,
    bdi,
    bdo,
    br,
    cite,
    code,
    data,
    time,
    dfn,
    em,
    i,
    kbd,
    mark,
    q,
    blockquote,
    rp,
    ruby,
    rt,
    rtc,
    rb,
    s,
    del,
    ins,
    samp,
    small,
    span,
    strong,
    sub,
    sup,
    u,
    @"var",
    wbr,
    area,
    map,
    audio,
    source,
    track,
    video,
    embed,
    object,
    param,
    canvas,
    noscript,
    caption,
    table,
    col,
    colgroup,
    tbody,
    tr,
    thead,
    tfoot,
    td,
    th,
    button,
    datalist,
    option,
    fieldset,
    label,
    form,
    input,
    keygen,
    legend,
    meter,
    optgroup,
    select,
    output,
    progress,
    textarea,
    details,
    dialog,
    menuitem,
    summary,
    content,
    element,
    shadow,
    template,
    acronym,
    applet,
    basefont,
    font,
    big,
    blink,
    center,
    command,
    dir,
    frame,
    frameset,
    isindex,
    listing,
    marquee,
    noembed,
    plaintext,
    spacer,
    strike,
    tt,
    xmp,
    // SVG Tags
    animate,
    animateMotion,
    animateTransform,
    circle,
    clipPath,
    defs,
    desc,
    ellipse,
    feBlend,
    feColorMatrix,
    feComponentTransfer,
    feComposite,
    feConvolveMatrix,
    feDiffuseLighting,
    feDisplacementMap,
    feDistantLight,
    feDropShadow,
    feFlood,
    feFuncA,
    feFuncB,
    feFuncG,
    feFuncR,
    feGaussianBlur,
    feImage,
    feMerge,
    feMergeNode,
    feMorphology,
    feOffset,
    fePointLight,
    feSpecularLighting,
    feSpotLight,
    feTile,
    feTurbulence,
    filter,
    foreignObject,
    g,
    image,
    line,
    linearGradient,
    marker,
    mask,
    metadata,
    mpath,
    path,
    pattern,
    polygon,
    polyline,
    radialGradient,
    rect,
    set,
    stop,
    svg,
    @"switch",
    symbol,
    text,
    textPath,
    tspan,
    use,
    view,
};
const SELF_CLOSING_ONLY: []const ElementTag = &.{ .br, .hr, .img, .input, .link, .source, .track, .wbr };
const NO_CHILDREN_ONLY: []const ElementTag = &.{ .meta, .link, .input };

fn isSelfClosing(tag: ElementTag) bool {
    return std.mem.indexOfScalar(ElementTag, SELF_CLOSING_ONLY, tag) != null;
}

fn isNoClosing(tag: ElementTag) bool {
    return std.mem.indexOfScalar(ElementTag, NO_CHILDREN_ONLY, tag) != null;
}

/// Escapes: & < > " '
fn escapeHtmlAttrVal(writer: *std.Io.Writer, value: []const u8) !void {
    for (value) |char| {
        switch (char) {
            '&' => try writer.writeAll("&amp;"),
            '<' => try writer.writeAll("&lt;"),
            '>' => try writer.writeAll("&gt;"),
            '"' => try writer.writeAll("&quot;"),
            '\'' => try writer.writeAll("&#x27;"),
            else => try writer.writeByte(char),
        }
    }
}

/// Escapes: & < >
fn escapHtmlTextNode(writer: *std.Io.Writer, value: []const u8) !void {
    for (value) |char| {
        switch (char) {
            '&' => try writer.writeAll("&amp;"),
            '<' => try writer.writeAll("&lt;"),
            '>' => try writer.writeAll("&gt;"),
            else => try writer.writeByte(char),
        }
    }
}

fn unescapeHtmlToWriter(writer: *std.Io.Writer, value: []const u8) !void {
    var i: usize = 0;
    while (i < value.len) {
        if (value[i] == '&') {
            // Check for HTML entities
            if (i + 4 <= value.len and std.mem.eql(u8, value[i .. i + 4], "&lt;")) {
                try writer.writeByte('<');
                i += 4;
            } else if (i + 4 <= value.len and std.mem.eql(u8, value[i .. i + 4], "&gt;")) {
                try writer.writeByte('>');
                i += 4;
            } else if (i + 5 <= value.len and std.mem.eql(u8, value[i .. i + 5], "&amp;")) {
                try writer.writeByte('&');
                i += 5;
            } else if (i + 6 <= value.len and std.mem.eql(u8, value[i .. i + 6], "&quot;")) {
                try writer.writeByte('"');
                i += 6;
            } else if (i + 6 <= value.len and std.mem.eql(u8, value[i .. i + 6], "&#x27;")) {
                try writer.writeByte('\'');
                i += 6;
            } else {
                // Not a recognized entity, write the ampersand as-is
                try writer.writeByte(value[i]);
                i += 1;
            }
        } else {
            try writer.writeByte(value[i]);
            i += 1;
        }
    }
}

/// Coerce props to the target struct type, handling defaults
fn coerceProps(comptime TargetType: type, props: anytype) TargetType {
    const TargetInfo = @typeInfo(TargetType);
    if (TargetInfo != .@"struct") {
        @compileError("Target type must be a struct");
    }

    const fields = TargetInfo.@"struct".fields;
    var result: TargetType = undefined;

    inline for (fields) |field| {
        if (@hasField(@TypeOf(props), field.name)) {
            @field(result, field.name) = @field(props, field.name);
        } else if (field.defaultValue()) |default_value| {
            @field(result, field.name) = default_value;
        } else {
            @compileError(std.fmt.comptimePrint("Missing required attribute `{s}` in Component `{s}`", .{ field.name, @typeName(TargetType) }));
        }
    }

    return result;
}

pub const Component = union(enum) {
    pub const Serializable = devtool.ComponentSerializable;

    none,
    text: []const u8,
    element: Element,
    component_fn: ComponentFn,
    component_csr: ComponentCsr,
    /// Reactive signal text - updates automatically when signal changes
    signal_text: SignalText,

    /// A text node bound to a Signal for fine-grained reactivity
    pub const SignalText = struct {
        /// The signal's unique ID for DOM binding
        signal_id: u64,
        /// The current text value (for initial render)
        current_text: []const u8,
    };

    pub const ComponentCsr = struct {
        name: []const u8,
        id: []const u8,
        props_ptr: ?*const anyopaque = null,
        writeProps: ?*const fn (*std.Io.Writer, *const anyopaque) anyerror!void = null,
        getStateItems: ?*const fn (std.mem.Allocator, *const anyopaque) anyerror![]const devtool.ComponentSerializable.StateItem = null,
        /// SSR-rendered content of the component (for hydration)
        children: ?*const Component = null,
        /// Whether this is a React component (uses JSON) or Zig component (uses ZON)
        is_react: bool = false,
    };

    pub const ComponentFn = struct {
        propsPtr: ?*const anyopaque,
        callFn: *const fn (propsPtr: ?*const anyopaque, allocator: Allocator) anyerror!Component,
        getStateItems: ?*const fn (std.mem.Allocator, *const anyopaque) anyerror![]const devtool.ComponentSerializable.StateItem = null,
        allocator: Allocator,
        deinitFn: ?*const fn (propsPtr: ?*const anyopaque, allocator: Allocator) void,
        async_mode: BuiltinAttribute.Async = .sync,
        fallback: ?*const Component = null,
        caching: ?BuiltinAttribute.Caching = null,
        name: []const u8,

        pub fn init(comptime func: anytype, name: []const u8, allocator: Allocator, props: anytype) ComponentFn {
            const FuncInfo = @typeInfo(@TypeOf(func));
            const param_count = FuncInfo.@"fn".params.len;
            const fn_name = @typeName(@TypeOf(func));

            // Validation of parameters
            if (param_count != 1 and param_count != 2)
                @compileError(std.fmt.comptimePrint("{s} must have 1 or 2 parameters found {d} parameters", .{ fn_name, param_count }));

            const FirstPropType = FuncInfo.@"fn".params[0].type.?;
            const first_is_allocator = FirstPropType == std.mem.Allocator;
            const first_is_ctx_ptr = @typeInfo(FirstPropType) == .pointer and
                @hasField(@typeInfo(FirstPropType).pointer.child, "allocator") and
                @hasField(@typeInfo(FirstPropType).pointer.child, "children");

            if (!first_is_allocator and !first_is_ctx_ptr)
                @compileError("Component " ++ fn_name ++ " must have allocator or *ComponentCtx as the first parameter");

            // If two parameters are passed with allocator first, the props type must be a struct
            if (first_is_allocator and param_count == 2) {
                const SecondPropType = FuncInfo.@"fn".params[1].type.?;
                if (@typeInfo(SecondPropType) != .@"struct")
                    @compileError("Component" ++ fn_name ++ " must have a struct as the second parameter, found " ++ @typeName(SecondPropType));
            }

            // Context-based components should only have 1 parameter
            if (first_is_ctx_ptr and param_count != 1)
                @compileError("Component " ++ fn_name ++ " with *ComponentCtx must have exactly 1 parameter");

            // Allocate props on heap to persist
            const props_copy = if (first_is_allocator and param_count == 2) blk: {
                const SecondPropType = FuncInfo.@"fn".params[1].type.?;
                const coerced = coerceProps(SecondPropType, props);
                const p = allocator.create(SecondPropType) catch @panic("OOM");
                p.* = coerced;
                break :blk p;
            } else if (first_is_ctx_ptr) blk: {
                // Contexted components
                const CtxType = @typeInfo(FirstPropType).pointer.child;
                const ctx = allocator.create(CtxType) catch @panic("OOM");
                ctx.allocator = allocator;
                // Children from props if present
                ctx.children = if (@hasField(@TypeOf(props), "children")) props.children else null;
                // fn Component(ctx: *ComponentCtx(Props)) zx.Component
                if (@hasField(CtxType, "props")) {
                    const PropsFieldType = @FieldType(CtxType, "props");
                    if (PropsFieldType != void) {
                        ctx.props = coerceProps(PropsFieldType, props);
                    }
                }
                break :blk ctx;
            } else null;

            const Wrapper = struct {
                // Check if the function returns an optional type
                const ReturnType = FuncInfo.@"fn".return_type.?;
                const returns_optional = @typeInfo(ReturnType) == .optional;
                const returns_error_union = @typeInfo(ReturnType) == .error_union;
                const inner_is_optional = returns_error_union and @typeInfo(@typeInfo(ReturnType).error_union.payload) == .optional;

                /// Normalize any return type (Component, ?Component, !Component, !?Component) to anyerror!Component
                fn normalize(result: anytype) anyerror!Component {
                    const T = @TypeOf(result);
                    if (T == Component) {
                        return result;
                    }
                    // ?Component -> return .none if null
                    if (@typeInfo(T) == .optional) {
                        return result orelse .none;
                    }
                    // !Component or !?Component
                    if (@typeInfo(T) == .error_union) {
                        const payload = try result;
                        // Check if payload is optional
                        if (@typeInfo(@TypeOf(payload)) == .optional) {
                            return payload orelse .none;
                        }
                        return payload;
                    }
                    return result;
                }

                fn call(propsPtr: ?*const anyopaque, alloc: Allocator) anyerror!Component {
                    if (first_is_ctx_ptr) {
                        const CtxType = @typeInfo(FirstPropType).pointer.child;
                        const ctx_ptr: *CtxType = @ptrCast(@alignCast(@constCast(propsPtr orelse @panic("ctx is null"))));
                        return normalize(func(ctx_ptr));
                    }
                    if (first_is_allocator and param_count == 1) {
                        return normalize(func(alloc));
                    }
                    if (first_is_allocator and param_count == 2) {
                        const SecondPropType = FuncInfo.@"fn".params[1].type.?;
                        const p = propsPtr orelse @panic("propsPtr is null for function with props");
                        const typed_p: *const SecondPropType = @ptrCast(@alignCast(p));
                        return normalize(func(alloc, typed_p.*));
                    }
                    unreachable;
                }

                fn deinit(propsPtr: ?*const anyopaque, alloc: Allocator) void {
                    if (first_is_ctx_ptr) {
                        const CtxType = @typeInfo(FirstPropType).pointer.child;
                        const ctx_ptr: *CtxType = @ptrCast(@alignCast(@constCast(propsPtr orelse return)));
                        alloc.destroy(ctx_ptr);
                        return;
                    }
                    if (first_is_allocator and param_count == 2) {
                        const SecondPropType = FuncInfo.@"fn".params[1].type.?;
                        const p = propsPtr orelse @panic("propsPtr is null for function with props");
                        const typed_p: *const SecondPropType = @ptrCast(@alignCast(p));
                        alloc.destroy(typed_p);
                    }
                }
            };

            return .{
                .propsPtr = props_copy,
                .callFn = Wrapper.call,
                .getStateItems = devtool.createGetStateItemsFn(func),
                .allocator = allocator,
                .deinitFn = Wrapper.deinit,
                .name = name,
            };
        }

        pub fn call(self: ComponentFn) anyerror!Component {
            return self.callFn(self.propsPtr, self.allocator);
        }

        pub fn deinit(self: ComponentFn) void {
            if (self.deinitFn) |deinit_fn| {
                deinit_fn(self.propsPtr, self.allocator);
            }
        }
    };

    /// Free allocated memory recursively
    /// Note: Only frees what was allocated by ZxContext.zx()
    /// Inline struct data is not freed (and will cause no issues as it's stack data)
    pub fn deinit(self: Component, allocator: std.mem.Allocator) void {
        switch (self) {
            .none, .text, .signal_text => {},
            .element => |elem| {
                if (elem.children) |children| {
                    // Recursively free children (e.g., Button() results)
                    for (children) |child| {
                        child.deinit(allocator);
                    }
                    // Free the children array itself
                    allocator.free(children);
                }
                if (elem.attributes) |attributes| {
                    allocator.free(attributes);
                }
            },
            .component_fn => |func| {
                // Free the props that were allocated
                func.deinit();
            },
            .component_csr => |component_csr| {
                allocator.free(component_csr.name);
                allocator.free(component_csr.id);
            },
        }
    }

    pub fn render(self: Component, writer: *std.Io.Writer) !void {
        try self.renderInner(writer, .{ .escaping = .html, .rendering = .server });
    }

    pub const streaming_bootstrap_script =
        \\<script>window.$ZX=function(id,html){var t=document.getElementById('__ZX_S-'+id);if(t){var d=document.createElement('div');d.innerHTML=html;while(d.firstChild)t.parentNode.insertBefore(d.firstChild,t);t.remove();}}</script>
    ;

    /// Async component collected during streaming
    pub const AsyncComponent = struct {
        id: u32,
        component: Component,

        pub fn renderScript(self: AsyncComponent, allocator: std.mem.Allocator) ![]const u8 {
            var aw = std.io.Writer.Allocating.init(allocator);
            errdefer aw.deinit();

            try self.component.render(&aw.writer);
            const html = aw.written();

            // Build minimal script: <script>$ZX(id,`content`)</script>
            var script_writer = std.io.Writer.Allocating.init(allocator);
            errdefer script_writer.deinit();

            try script_writer.writer.print("<script>$ZX({d},`", .{self.id});

            // Escape backticks, backslashes, and $ in HTML for template literal
            for (html) |c| {
                switch (c) {
                    '`' => try script_writer.writer.writeAll("\\`"),
                    '\\' => try script_writer.writer.writeAll("\\\\"),
                    '$' => try script_writer.writer.writeAll("\\$"),
                    else => try script_writer.writer.writeByte(c),
                }
            }

            try script_writer.writer.writeAll("`)</script>");

            return script_writer.written();
        }
    };

    /// Stream method that renders HTML while collecting async components
    /// Writes placeholders for @async={.stream} components and returns them for parallel rendering
    pub fn stream(self: Component, allocator: std.mem.Allocator, writer: *std.Io.Writer) ![]AsyncComponent {
        var async_components = std.array_list.Managed(AsyncComponent).init(allocator);
        errdefer async_components.deinit();

        var counter: u32 = 0;
        try self.renderInner(writer, .{
            .escaping = .html,
            .rendering = .server,
            .async_components = &async_components,
            .async_counter = &counter,
        });
        return async_components.toOwnedSlice();
    }

    const RenderInnerOptions = struct {
        escaping: ?BuiltinAttribute.Escaping = .html,
        rendering: ?BuiltinAttribute.Rendering = .server,
        async_components: ?*std.array_list.Managed(AsyncComponent) = null,
        async_counter: ?*u32 = null,
    };
    fn renderInner(self: Component, writer: *std.Io.Writer, options: RenderInnerOptions) !void {
        switch (self) {
            .none => {
                // Render nothing
            },
            .text => |text| {
                if (options.escaping == .none) {
                    try unescapeHtmlToWriter(writer, text);
                } else {
                    try writer.print("{s}", .{text});
                }
            },
            .component_fn => |func| {
                // Check for component-level caching
                if (func.caching) |caching| {
                    if (caching.seconds > 0) {
                        // Generate cache key from function pointer + props pointer + optional custom key
                        var key_buf: [128]u8 = undefined;
                        const generated_key = if (caching.key) |custom_key|
                            std.fmt.bufPrint(&key_buf, "cmp:{s}:{x}:{x}", .{
                                custom_key,
                                @intFromPtr(func.callFn),
                                @intFromPtr(func.propsPtr),
                            }) catch null
                        else
                            std.fmt.bufPrint(&key_buf, "cmp:{x}:{x}", .{
                                @intFromPtr(func.callFn),
                                @intFromPtr(func.propsPtr),
                            }) catch null;

                        if (generated_key) |key| {
                            // Try to get from cache
                            if (cache.get(key)) |cached_html| {
                                try writer.writeAll(cached_html);
                                return;
                            }

                            // Render to buffer for caching
                            var buf_writer = std.Io.Writer.Allocating.init(func.allocator);
                            const component = try func.call();
                            try component.renderInner(&buf_writer.writer, options);

                            const rendered = buf_writer.written();
                            cache.put(key, rendered, caching.seconds);

                            // Write to actual output
                            try writer.writeAll(rendered);
                            return;
                        }
                    }
                }

                // No caching or cache miss - render directly
                const component = try func.call();
                try component.renderInner(writer, options);
            },
            .component_csr => |component_csr| {
                // Start comment marker format: <!--$id {"prop":"value"}--> (JSON)
                // Both React and Zig components use JSON format
                if (component_csr.is_react) {
                    // React component: use JSON format
                    if (component_csr.writeProps) |writeProps| {
                        if (component_csr.props_ptr) |props_ptr| {
                            try writer.print("<!--${s} {s} ", .{ component_csr.id, component_csr.name });
                            try writeProps(writer, props_ptr);
                            try writer.print("-->", .{});
                        } else {
                            try writer.print("<!--${s} {s}-->", .{ component_csr.id, component_csr.name });
                        }
                    } else {
                        try writer.print("<!--${s} {s}-->", .{ component_csr.id, component_csr.name });
                    }
                } else {
                    // Zig component: use JSON format (same as React)
                    if (component_csr.writeProps) |writeProps| {
                        if (component_csr.props_ptr) |props_ptr| {
                            try writer.print("<!--${s} ", .{component_csr.id});
                            try writeProps(writer, props_ptr);
                            try writer.print("-->", .{});
                        } else {
                            try writer.print("<!--${s}-->", .{component_csr.id});
                        }
                    } else {
                        // No props - just marker
                        try writer.print("<!--${s}-->", .{component_csr.id});
                    }
                }

                // Render SSR content
                if (component_csr.children) |children| {
                    try children.renderInner(writer, options);
                }

                // End comment marker: <!--/$id-->
                try writer.print("<!--/${s}-->", .{component_csr.id});
            },
            .signal_text => |sig| {
                if (options.escaping == .none) {
                    try unescapeHtmlToWriter(writer, sig.current_text);
                } else {
                    try writer.print("{s}", .{sig.current_text});
                }
            },
            .element => |elem| {
                // Check if this element is async and we're collecting async components
                if (options.async_components != null and elem.async == .stream) {
                    const async_id = options.async_counter.?.*;
                    options.async_counter.?.* += 1;

                    // Write placeholder div with fallback content
                    try writer.print("<div id=\"__ZX_S-{d}\">", .{async_id});

                    // Render fallback content if provided
                    if (elem.fallback) |fallback| {
                        try fallback.*.renderInner(writer, .{
                            .escaping = options.escaping,
                            .rendering = options.rendering,
                        });
                    }

                    try writer.writeAll("</div>");

                    // Collect for async rendering
                    try options.async_components.?.append(.{
                        .id = async_id,
                        .component = self,
                    });
                    return;
                }

                // <><div>...</div></> => <div>...</div>
                if (elem.tag == .fragment) {
                    if (elem.children) |children| {
                        for (children) |child| {
                            try child.renderInner(writer, options);
                        }
                    }
                    return;
                }

                // Otherwise, render normally
                // Opening tag
                try writer.print("<{s}", .{@tagName(elem.tag)});

                const is_self_closing = isSelfClosing(elem.tag);
                const is_no_closing = isNoClosing(elem.tag);

                // Handle attributes
                if (elem.attributes) |attributes| {
                    for (attributes) |attribute| {
                        if (attribute.handler) |handler| {
                            // try writer.print(" {s}", .{attribute.name});
                            // try handler(.{});
                            _ = handler;
                        } else {
                            try writer.print(" {s}", .{attribute.name});
                        }
                        if (attribute.value) |value| {
                            try writer.writeAll("=\"");
                            try escapeHtmlAttrVal(writer, value);
                            try writer.writeAll("\"");
                        }
                    }
                }

                // Closing bracket
                if (!is_self_closing or is_no_closing) {
                    try writer.print(">", .{});
                } else {
                    try writer.print(" />", .{});
                }

                // Render children (recursively collect slots if needed)
                if (elem.children) |children| {
                    // Use element's escaping setting if set, otherwise inherit from parent
                    const child_options = RenderInnerOptions{
                        .escaping = elem.escaping orelse options.escaping,
                        .rendering = elem.rendering orelse options.rendering,
                        .async_components = options.async_components,
                        .async_counter = options.async_counter,
                    };
                    for (children) |child| {
                        try child.renderInner(writer, child_options);
                    }
                }

                // Closing tag
                if (!is_self_closing and !is_no_closing) {
                    try writer.print("</{s}>", .{@tagName(elem.tag)});
                }
            },
        }
    }

    pub fn action(self: @This(), _: anytype, _: anytype, res: anytype) !void {
        res.content_type = .HTML;
        try self.render(&res.buffer.writer);
    }

    /// Recursively search for an element by tag name
    /// Returns a mutable pointer to the Component if found, null otherwise
    /// Note: Resolves component_fn lazily during search
    /// Note: Requires allocator to make children mutable if needed
    pub fn getElementByName(self: *Component, allocator: std.mem.Allocator, tag: ElementTag) ?*Component {
        switch (self.*) {
            .element => |*elem| {
                if (elem.tag == tag) {
                    return self;
                }
                // Search in children - need to make children mutable first if they're const
                if (elem.children) |children| {
                    // Allocate mutable copy of children for searching
                    const mutable_children = allocator.alloc(Component, children.len) catch return null;
                    @memcpy(mutable_children, children);
                    elem.children = mutable_children;

                    for (0..mutable_children.len) |i| {
                        var child_mut = &mutable_children[i];
                        if (child_mut.getElementByName(allocator, tag)) |found| {
                            return found;
                        }
                    }
                }
                return null;
            },
            .component_fn => |*func| {
                // Resolve the component function and replace self with the result
                const resolved = func.call() catch return null;
                self.* = resolved;
                // Now search the resolved component
                return self.getElementByName(allocator, tag);
            },
            .none, .text, .component_csr, .signal_text => return null,
        }
    }

    /// Append a child component to an element
    /// Only works if this Component is an element variant
    /// Note: Allocates a new array since children may be const
    pub fn appendChild(self: *Component, allocator: std.mem.Allocator, child: Component) !void {
        switch (self.*) {
            .element => |*elem| {
                if (elem.children) |existing_children| {
                    // Allocate new array and copy existing children + new child
                    const new_children = try allocator.alloc(Component, existing_children.len + 1);
                    @memcpy(new_children[0..existing_children.len], existing_children);
                    new_children[existing_children.len] = child;
                    elem.children = new_children;
                } else {
                    // Allocate new array
                    const new_children = try allocator.alloc(Component, 1);
                    new_children[0] = child;
                    elem.children = new_children;
                }
            },
            else => return error.NotAnElement,
        }
    }

    pub const SerializeOptions = struct {
        only_components: bool = true,
        include_props: bool = true,
        include_attributes: bool = true,
    };

    pub fn format(
        self: *const Component,
        w: *std.Io.Writer,
    ) error{WriteFailed}!void {
        self.formatWithOptions(w, .{}) catch return error.WriteFailed;
    }

    pub fn formatWithOptions(
        self: *const Component,
        w: *std.Io.Writer,
        options: SerializeOptions,
    ) anyerror!void {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        var serializable = try devtool.ComponentSerializable.init(allocator, self.*, options);
        try serializable.serialize(w);
    }
};

pub const Element = struct {
    pub const Attribute = struct {
        name: []const u8,
        value: ?[]const u8 = null,
        handler: ?EventHandler = null,
    };

    tag: ElementTag,
    children: ?[]const Component = null,
    attributes: ?[]const Element.Attribute = null,

    escaping: ?BuiltinAttribute.Escaping = .html,
    rendering: ?BuiltinAttribute.Rendering = .server,
    async: ?BuiltinAttribute.Async = .sync,
    fallback: ?*const Component = null,
};

pub const ClientComponentOptions = struct {
    name: []const u8,
    path: []const u8,
    id: []const u8,
};

pub const ComponentClientOptions = struct {
    name: []const u8,
    id: []const u8,
};
const ZxOptions = struct {
    children: ?[]const Component = null,
    attributes: ?[]const Element.Attribute = null,
    allocator: ?std.mem.Allocator = null,
    escaping: ?BuiltinAttribute.Escaping = .html,
    rendering: ?BuiltinAttribute.Rendering = .server,
    async: ?BuiltinAttribute.Async = .sync,
    fallback: ?*const Component = null,
    caching: ?BuiltinAttribute.Caching = null,
    client: ?ComponentClientOptions = null,
};

pub fn zx(tag: ElementTag, options: ZxOptions) Component {
    return .{ .element = .{
        .tag = tag,
        .children = options.children,
        .attributes = options.attributes,
    } };
}

/// Create a lazy component from a function
/// The function will be invoked during rendering, allowing for dynamic slot handling
/// Supports functions with 0 params (), 1 param (allocator), or 2 params (allocator, props)
pub fn lazy(allocator: Allocator, comptime func: anytype, props: anytype) Component {
    return .{ .component_fn = Component.ComponentFn.init(func, allocator, props) };
}

/// Check at comptime if a type is a Signal struct (value, not pointer)
fn isSignalValue(comptime T: type) bool {
    if (@typeInfo(T) != .@"struct") return false;

    // Check for Signal's characteristic fields and declarations
    return @hasField(T, "id") and
        @hasField(T, "value") and
        @hasDecl(T, "get") and
        @hasDecl(T, "set") and
        @hasDecl(T, "notifyChange");
}

/// Check at comptime if a type is a pointer to a Signal struct
fn isSignalPointer(comptime T: type) bool {
    const type_info = @typeInfo(T);
    if (type_info != .pointer) return false;
    if (type_info.pointer.size != .one) return false;

    return isSignalValue(type_info.pointer.child);
}

/// Check at comptime if a type is a Computed struct (value, not pointer)
fn isComputedValue(comptime T: type) bool {
    if (@typeInfo(T) != .@"struct") return false;

    // Check for Computed's characteristic fields: source, compute, id, and subscribe
    return @hasField(T, "source") and
        @hasField(T, "compute") and
        @hasField(T, "id") and
        @hasDecl(T, "get") and
        @hasDecl(T, "subscribe");
}

/// Check at comptime if a type is a pointer to a Computed struct
fn isComputedPointer(comptime T: type) bool {
    const type_info = @typeInfo(T);
    if (type_info != .pointer) return false;
    if (type_info.pointer.size != .one) return false;

    return isComputedValue(type_info.pointer.child);
}

/// Get the value type from a Computed pointer type
fn ComputedValueType(comptime T: type) type {
    const type_info = @typeInfo(T);
    if (type_info == .pointer) {
        const Child = type_info.pointer.child;
        if (@typeInfo(Child) == .@"struct" and @hasField(Child, "value")) {
            return @FieldType(Child, "value");
        }
    }
    @compileError("Expected a pointer to a Computed type");
}

/// Format a Signal's value to a string for DOM text content
fn formatSignalValue(comptime T: type, value: T, allocator: Allocator) []const u8 {
    return switch (@typeInfo(T)) {
        .int, .comptime_int => std.fmt.allocPrint(allocator, "{d}", .{value}) catch "?",
        .float, .comptime_float => std.fmt.allocPrint(allocator, "{d:.2}", .{value}) catch "?",
        .bool => if (value) "true" else "false",
        .pointer => |ptr_info| blk: {
            if (ptr_info.size == .slice and ptr_info.child == u8) {
                break :blk allocator.dupe(u8, value) catch "?";
            }
            break :blk std.fmt.allocPrint(allocator, "{any}", .{value}) catch "?";
        },
        .@"enum" => @tagName(value),
        .optional => if (value) |v| formatSignalValue(@TypeOf(v), v, allocator) else "",
        else => std.fmt.allocPrint(allocator, "{any}", .{value}) catch "?",
    };
}

/// Context for creating components with allocator support
pub const ZxContext = struct {
    allocator: ?std.mem.Allocator = null,

    pub fn getAlloc(self: *ZxContext) std.mem.Allocator {
        return self.allocator orelse @panic("Allocator not set. Please provide @allocator attribute to the parent element.");
    }

    fn escapeHtml(self: *ZxContext, text: []const u8) []const u8 {
        // On browser, DOM APIs (textContent) handle escaping automatically
        // We only need to escape when generating HTML strings on the server
        // TODO: we would want to move the escaping logic at the time of rendering the element, and simply not use escapeHtml for client side rendering
        if (platform == .browser) return text;

        const allocator = self.getAlloc();
        // Use a buffer writer to leverage the shared escaping logic
        // For text content, we only escape & < > (not quotes)
        var aw = std.io.Writer.Allocating.init(allocator);
        escapHtmlTextNode(&aw.writer, text) catch @panic("OOM");
        return aw.written();
    }

    pub fn ele(self: *ZxContext, tag: ElementTag, options: ZxOptions) Component {
        // Set allocator from @allocator option if provided
        if (options.allocator) |allocator| {
            self.allocator = allocator;
        }

        const allocator = self.getAlloc();

        // Allocate and copy children if provided
        const children_copy = if (options.children) |children| blk: {
            const copy = allocator.alloc(Component, children.len) catch @panic("OOM");
            @memcpy(copy, children);
            break :blk copy;
        } else null;

        // Allocate and copy attributes if provided
        const attributes_copy = if (options.attributes) |attributes| blk: {
            const copy = allocator.alloc(Element.Attribute, attributes.len) catch @panic("OOM");
            @memcpy(copy, attributes);
            break :blk copy;
        } else null;

        return .{ .element = .{
            .tag = tag,
            .children = children_copy,
            .attributes = attributes_copy,
            .escaping = options.escaping,
            .rendering = options.rendering,
            .async = options.async,
            .fallback = options.fallback,
        } };
    }

    pub fn txt(self: *ZxContext, text: []const u8) Component {
        const escaped = self.escapeHtml(text);
        return .{ .text = escaped };
    }

    pub fn expr(self: *ZxContext, val: anytype) Component {
        const T = @TypeOf(val);

        if (T == Component) return val;

        // Check if it's a Signal pointer - enable fine-grained reactivity
        if (comptime isSignalPointer(T)) {
            const allocator = self.getAlloc();
            // Ensure the signal has a runtime ID for DOM binding
            val.ensureId();
            // Format the current value as text
            const ValueType = Client.reactivity.SignalValueType(T);
            const current_value = val.get();
            const text = formatSignalValue(ValueType, current_value, allocator);
            return .{ .signal_text = .{
                .signal_id = val.id,
                .current_text = text,
            } };
        }

        // Check if it's a Computed pointer - enable fine-grained reactivity like Signal
        if (comptime isComputedPointer(T)) {
            const allocator = self.getAlloc();
            // Ensure the computed has a runtime ID and subscribes to source
            val.ensureId();
            @constCast(val).subscribe();
            // Format the current value as text
            const ValueType = ComputedValueType(T);
            const current_value = val.get();
            const text = formatSignalValue(ValueType, current_value, allocator);
            return .{ .signal_text = .{
                .signal_id = val.id,
                .current_text = text,
            } };
        }

        // Check if it's a Signal VALUE (not pointer) - compile error with helpful message
        if (comptime isSignalValue(T)) {
            @compileError(
                \\Signal passed by value - reactivity won't work.
                \\Use `{&signal}` instead of `{signal}` to enable reactive updates.
                \\
                \\Example: <h5>{&count}</h5> instead of <h5>{count}</h5>
            );
        }

        // Check if it's a Computed VALUE (not pointer) - compile error with helpful message
        if (comptime isComputedValue(T)) {
            @compileError(
                \\Computed passed by value - reactivity won't work.
                \\Use `{&computed}` instead of `{computed}` to enable reactive updates.
                \\
                \\Example: <h5>{&doubled}</h5> instead of <h5>{doubled}</h5>
            );
        }

        const Cmp = switch (@typeInfo(T)) {
            .comptime_int, .comptime_float, .float => self.fmt("{d}", .{val}),
            .int => if (T == u8 and std.ascii.isPrint(val))
                self.fmt("{c}", .{val})
            else
                self.fmt("{d}", .{val}),
            .bool => self.fmt("{s}", .{if (val) "true" else "false"}),
            .null => self.ele(.fragment, .{}), // Render nothing for null
            .optional => if (val) |inner| self.expr(inner) else self.ele(.fragment, .{}),
            .@"enum", .enum_literal => self.txt(@tagName(val)),
            .pointer => |ptr_info| switch (ptr_info.size) {
                .one => switch (@typeInfo(ptr_info.child)) {
                    .array => {
                        // Coerce `*[N]T` to `[]const T`.
                        const Slice = []const std.meta.Elem(ptr_info.child);
                        return self.expr(@as(Slice, val));
                    },
                    else => {
                        return self.expr(val.*);
                    },
                },
                .many, .slice => {
                    if (ptr_info.size == .many and ptr_info.sentinel() == null)
                        @compileError("unable to stringify type '" ++ @typeName(T) ++ "' without sentinel");
                    const slice = if (ptr_info.size == .many) std.mem.span(val) else val;

                    if (ptr_info.child == u8) {
                        // This is a []const u8, or some similar Zig string.
                        if (std.unicode.utf8ValidateSlice(slice)) {
                            return txt(self, slice);
                        }
                    }

                    // Handle slices of Components
                    if (ptr_info.child == Component) {
                        return .{ .element = .{
                            .tag = .fragment,
                            .children = val,
                        } };
                    }

                    return self.txt(slice);
                },

                else => @compileError("Unable to render type '" ++ @typeName(T) ++ "', supported types are: int, float, bool, string, enum, optional"),
            },
            .@"struct" => |struct_info| {
                var aw = std.io.Writer.Allocating.init(self.getAlloc());
                defer aw.deinit();

                // aw.writer.print("{s} ", .{@tagName(struct_info)}) catch @panic("OOM");
                _ = struct_info;
                std.zon.stringify.serializeMaxDepth(val, .{ .whitespace = true }, &aw.writer, 100) catch |err| {
                    return self.fmt("{s}", .{@errorName(err)});
                };

                return self.txt(aw.written());
            },
            .array => |arr_info| {
                // Handle arrays of Components
                if (arr_info.child == Component) {
                    return .{ .element = .{
                        .tag = .fragment,
                        .children = &val,
                    } };
                }
                @compileError("Unable to render array of type '" ++ @typeName(arr_info.child) ++ "', only Component arrays are supported");
            },
            else => @compileError("Unable to render type '" ++ @typeName(T) ++ "', supported types are: int, float, bool, string, enum, optional"),
        };

        return Cmp;
    }

    pub fn fmt(self: *ZxContext, comptime format: []const u8, args: anytype) Component {
        const allocator = self.getAlloc();
        const text = std.fmt.allocPrint(allocator, format, args) catch @panic("OOM");
        return .{ .text = text };
    }

    pub fn printf(self: *ZxContext, comptime format: []const u8, args: anytype) []const u8 {
        const allocator = self.getAlloc();
        const text = std.fmt.allocPrint(allocator, format, args) catch @panic("OOM");
        return text;
    }

    /// Create an attribute with type-aware value handling
    /// Returns null for values that should omit the attribute (false booleans, null optionals)
    pub fn attr(self: *ZxContext, comptime name: []const u8, val: anytype) ?Element.Attribute {
        const T = @TypeOf(val);

        return switch (@typeInfo(T)) {
            // Strings and function pointers
            .pointer => |ptr_info| blk: {
                if (ptr_info.size == .slice and ptr_info.child == u8) {
                    break :blk .{ .name = name, .value = val };
                }
                if (ptr_info.size == .one) {
                    if (@typeInfo(ptr_info.child) == .array) {
                        const Slice = []const std.meta.Elem(ptr_info.child);
                        return self.attr(name, @as(Slice, val));
                    }
                    // Function pointer - treat as event handler
                    if (@typeInfo(ptr_info.child) == .@"fn") {
                        break :blk .{ .name = name, .handler = val };
                    }
                }
                @compileError("Unsupported pointer type for attribute: " ++ @typeName(T));
            },

            // Integers - format to string
            .int, .comptime_int => .{
                .name = name,
                .value = self.printf("{d}", .{val}),
            },

            // Floats - format with default precision
            .float, .comptime_float => .{
                .name = name,
                .value = self.printf("{d}", .{val}),
            },

            // Booleans - presence-only attribute (true) or omit (false)
            .bool => if (val) .{ .name = name, .value = null } else null,

            // Optionals - recurse if non-null, omit if null
            .optional => if (val) |inner| self.attr(name, inner) else null,

            // Enums - convert tag name to string
            .@"enum", .enum_literal => .{
                .name = name,
                .value = @tagName(val),
            },

            // Event handlers - store as function pointer
            .@"fn" => .{
                .name = name,
                .handler = val,
            },
            else => @compileError("Unsupported type for attribute value: " ++ @typeName(T)),
        };
    }

    pub fn attrf(self: *ZxContext, comptime name: []const u8, comptime format: []const u8, args: anytype) ?Element.Attribute {
        const allocator = self.getAlloc();
        const text = std.fmt.allocPrint(allocator, format, args) catch @panic("OOM");
        return self.attr(name, text);
    }

    pub fn attrv(self: *ZxContext, val: anytype) []const u8 {
        const attrkv = self.attr("f", val);
        if (attrkv) |a| {
            return a.value orelse "";
        }
        return "";
    }

    pub fn propf(self: *ZxContext, comptime format: []const u8, args: anytype) []const u8 {
        const allocator = self.getAlloc();
        return std.fmt.allocPrint(allocator, format, args) catch @panic("OOM");
    }
    pub const propv = attrv;

    /// Filter and collect non-null attributes into a slice
    pub fn attrs(self: *ZxContext, inputs: anytype) []const Element.Attribute {
        const allocator = self.getAlloc();
        const InputType = @TypeOf(inputs);
        const input_info = @typeInfo(InputType);

        // Handle tuple/struct (comptime known)
        if (input_info == .@"struct" and input_info.@"struct".is_tuple) {
            // Count non-null attributes at runtime
            var count: usize = 0;
            inline for (inputs) |input| {
                if (@TypeOf(input) == ?Element.Attribute) {
                    if (input != null) count += 1;
                } else {
                    count += 1;
                }
            }

            if (count == 0) return &.{};

            const result = allocator.alloc(Element.Attribute, count) catch @panic("OOM");
            var idx: usize = 0;
            inline for (inputs) |input| {
                if (@TypeOf(input) == ?Element.Attribute) {
                    if (input) |a| {
                        result[idx] = a;
                        idx += 1;
                    }
                } else {
                    result[idx] = input;
                    idx += 1;
                }
            }

            return result;
        }

        @compileError("attrs() expects a tuple of attributes");
    }

    /// Spread a struct's fields as attributes
    /// Takes a struct and returns a slice of attributes for each field
    pub fn attrSpr(self: *ZxContext, props: anytype) []const ?Element.Attribute {
        const allocator = self.getAlloc();
        const T = @TypeOf(props);
        const type_info = @typeInfo(T);

        if (type_info != .@"struct") {
            @compileError("attrSpr() expects a struct, got " ++ @typeName(T));
        }

        const fields = type_info.@"struct".fields;
        if (fields.len == 0) return &.{};

        const result = allocator.alloc(?Element.Attribute, fields.len) catch @panic("OOM");

        inline for (fields, 0..) |field, i| {
            const val = @field(props, field.name);
            result[i] = self.attr(field.name, val);
        }

        return result;
    }

    /// Merge two structs for component props spreading
    /// Later fields override earlier ones
    pub fn propsM(_: *ZxContext, base: anytype, overrides: anytype) MergedPropsType(@TypeOf(base), @TypeOf(overrides)) {
        const BaseType = @TypeOf(base);
        const OverrideType = @TypeOf(overrides);
        const ResultType = MergedPropsType(BaseType, OverrideType);

        var result: ResultType = undefined;

        // Copy all fields from base
        const base_info = @typeInfo(BaseType);
        if (base_info == .@"struct") {
            inline for (base_info.@"struct".fields) |field| {
                if (@hasField(ResultType, field.name)) {
                    @field(result, field.name) = @field(base, field.name);
                }
            }
        }

        // Apply overrides (these take precedence)
        const override_info = @typeInfo(OverrideType);
        if (override_info == .@"struct") {
            inline for (override_info.@"struct".fields) |field| {
                @field(result, field.name) = @field(overrides, field.name);
            }
        }

        return result;
    }

    /// Merge multiple attribute sources (including spread results) into a single slice
    /// Accepts a tuple where each element can be:
    /// - ?Element.Attribute (single attribute from attr())
    /// - []const ?Element.Attribute (slice from attrSpr())
    /// Later attributes with the same name override earlier ones (like JSX)
    pub fn attrsM(self: *ZxContext, inputs: anytype) []const Element.Attribute {
        const allocator = self.getAlloc();
        const InputType = @TypeOf(inputs);
        const input_info = @typeInfo(InputType);

        if (input_info != .@"struct" or !input_info.@"struct".is_tuple) {
            @compileError("attrsM() expects a tuple of attributes or attribute slices");
        }

        // First pass: collect all attributes in order
        var count: usize = 0;
        inline for (inputs) |input| {
            const T = @TypeOf(input);
            if (T == ?Element.Attribute) {
                if (input != null) count += 1;
            } else if (T == []const ?Element.Attribute) {
                for (input) |maybe_attr| {
                    if (maybe_attr != null) count += 1;
                }
            } else {
                @compileError("attrsM() element must be ?Element.Attribute or []const ?Element.Attribute, got " ++ @typeName(T));
            }
        }

        if (count == 0) return &.{};

        // Collect all attributes in order (later ones override earlier)
        const temp = allocator.alloc(Element.Attribute, count) catch @panic("OOM");
        var idx: usize = 0;

        inline for (inputs) |input| {
            const T = @TypeOf(input);
            if (T == ?Element.Attribute) {
                if (input) |a| {
                    temp[idx] = a;
                    idx += 1;
                }
            } else if (T == []const ?Element.Attribute) {
                for (input) |maybe_attr| {
                    if (maybe_attr) |a| {
                        temp[idx] = a;
                        idx += 1;
                    }
                }
            }
        }

        // Deduplicate atrrs, keep last occurrence
        var unique_count: usize = 0;
        var i: usize = temp.len;
        while (i > 0) {
            i -= 1;
            const current = temp[i];
            var found_later = false;
            for (temp[i + 1 ..]) |later| {
                if (std.mem.eql(u8, current.name, later.name)) {
                    found_later = true;
                    break;
                }
            }
            if (!found_later) {
                unique_count += 1;
            }
        }

        const result = allocator.alloc(Element.Attribute, unique_count) catch @panic("OOM");
        var result_idx: usize = 0;

        for (temp, 0..) |current_attr, j| {
            var found_later = false;
            for (temp[j + 1 ..]) |later| {
                if (std.mem.eql(u8, current_attr.name, later.name)) {
                    found_later = true;
                    break;
                }
            }
            if (!found_later) {
                result[result_idx] = current_attr;
                result_idx += 1;
            }
        }

        allocator.free(temp);
        return result;
    }

    pub fn cmp(self: *ZxContext, comptime func: anytype, name: []const u8, options: ZxOptions, props: anytype) Component {
        const allocator = self.getAlloc();

        const FuncInfo = @typeInfo(@TypeOf(func));
        const param_count = FuncInfo.@"fn".params.len;
        const FirstPropType = FuncInfo.@"fn".params[0].type.?;
        const first_is_ctx_ptr = @typeInfo(FirstPropType) == .pointer and
            @hasField(@typeInfo(FirstPropType).pointer.child, "allocator") and
            @hasField(@typeInfo(FirstPropType).pointer.child, "children");

        // Context-based component or function with props parameter
        var comp_fn = if (first_is_ctx_ptr or param_count == 2) blk: {
            const PropsType = if (first_is_ctx_ptr) @TypeOf(props) else FuncInfo.@"fn".params[1].type.?;
            const coerced_props = coerceProps(PropsType, props);
            break :blk Component.ComponentFn.init(func, name, allocator, coerced_props);
        } else blk: {
            break :blk Component.ComponentFn.init(func, name, allocator, props);
        };

        // Apply builtin attributes from options
        comp_fn.async_mode = options.async orelse .sync;
        comp_fn.fallback = options.fallback;
        comp_fn.caching = options.caching;

        // If client option is set, return a client component (for @rendering={.client})
        // Render the component on the server for SSR, then hydrate on client
        if (options.client) |client_opts| {
            const name_copy = allocator.alloc(u8, client_opts.name.len) catch @panic("OOM");
            @memcpy(name_copy, client_opts.name);
            const id_copy = allocator.alloc(u8, client_opts.id.len) catch @panic("OOM");
            @memcpy(id_copy, client_opts.id);

            // Call the component function to get SSR content
            const rendered = comp_fn.call() catch @panic("Component call failed");
            const children_ptr = allocator.create(Component) catch @panic("OOM");
            children_ptr.* = rendered;

            // Get the full props type from the component function signature
            // and coerce partial props to include defaults - this ensures all fields are serialized
            const props_data = blk: {
                if (first_is_ctx_ptr) {
                    const CtxType = @typeInfo(FirstPropType).pointer.child;
                    if (@hasField(CtxType, "props")) {
                        const FullPropsType = @FieldType(CtxType, "props");
                        if (@typeInfo(FullPropsType) == .@"struct") {
                            const full_props = coerceProps(FullPropsType, props);
                            break :blk propsSerializer(FullPropsType, allocator, full_props);
                        }
                    }
                } else if (param_count == 2) {
                    const FullPropsType = FuncInfo.@"fn".params[1].type.?;
                    if (@typeInfo(FullPropsType) == .@"struct") {
                        const full_props = coerceProps(FullPropsType, props);
                        break :blk propsSerializer(FullPropsType, allocator, full_props);
                    }
                }
                // Fallback: serialize the props as-is
                break :blk propsSerializer(@TypeOf(props), allocator, props);
            };

            return .{
                .component_csr = .{
                    .name = name_copy,
                    .id = id_copy,
                    .props_ptr = props_data.ptr,
                    .writeProps = props_data.writeFn,
                    .children = children_ptr,
                },
            };
        }

        return .{ .component_fn = comp_fn };
    }

    /// Allocates a Component and returns a pointer to it (used for @fallback)
    pub fn ptr(self: *ZxContext, component: Component) *const Component {
        const allocator = self.getAlloc();
        const allocated = allocator.create(Component) catch @panic("OOM");
        allocated.* = component;
        return allocated;
    }

    /// Creates a React client-side rendered component.
    /// Uses JSON serialization for props to match React's expected format.
    pub fn client(self: *ZxContext, options: ClientComponentOptions, props: anytype) Component {
        const allocator = self.getAlloc();
        const Props = @TypeOf(props);

        const name_copy = allocator.alloc(u8, options.name.len) catch @panic("OOM");
        @memcpy(name_copy, options.name);
        const id_copy = allocator.alloc(u8, options.id.len) catch @panic("OOM");
        @memcpy(id_copy, options.id);

        // Use JSON serializer for React components
        const props_data = propsSerializerJson(Props, allocator, props);

        return .{
            .component_csr = .{
                .name = name_copy,
                .id = id_copy,
                .props_ptr = props_data.ptr,
                .writeProps = props_data.writeFn,
                .is_react = true,
            },
        };
    }
};

/// Returns props pointer and serializer function for direct-to-writer serialization at render time
/// Uses positional array format [val1, val2, ...] instead of JSON objects for smaller size.
/// Field names are known at compile time on both server and client, so we only need values.
fn propsSerializer(comptime Props: type, allocator: std.mem.Allocator, props: Props) struct {
    ptr: ?*const anyopaque,
    writeFn: ?*const fn (*std.Io.Writer, *const anyopaque) anyerror!void,
} {
    if (platform == .browser) return .{ .ptr = null, .writeFn = null };
    const type_info = @typeInfo(Props);

    if (type_info != .@"struct") return .{ .ptr = null, .writeFn = null };
    if (type_info.@"struct".fields.len == 0) return .{ .ptr = null, .writeFn = null };
    if (!comptime isPropsSerializable(Props)) {
        // @compileError("Props must be serializable");
        return .{ .ptr = null, .writeFn = null };
    }

    const props_copy = allocator.create(Props) catch return .{ .ptr = null, .writeFn = null };
    props_copy.* = props;

    return .{
        .ptr = props_copy,
        .writeFn = &struct {
            fn write(writer: *std.Io.Writer, ptr: *const anyopaque) anyerror!void {
                const typed_props: *const Props = @ptrCast(@alignCast(ptr));
                // Use positional array format: [val1, val2, ...] - no field names
                try serializePositional(Props, typed_props.*, writer);
            }
        }.write,
    };
}

/// This is internal and will change, do not use
pub const prop = struct {
    pub const serialize = serializePositional;
    pub const parse = hydration.parseProps;
};

/// Serialize a value in positional array format (structs become arrays, nested structs too)
pub fn serializePositional(comptime T: type, value: T, writer: *std.Io.Writer) anyerror!void {
    const type_info = @typeInfo(T);

    switch (type_info) {
        .@"struct" => |s| {
            // Structs become arrays: [field1_value, field2_value, ...]
            try writer.writeByte('[');
            inline for (s.fields, 0..) |field, i| {
                if (i > 0) try writer.writeByte(',');
                try serializePositional(field.type, @field(value, field.name), writer);
            }
            try writer.writeByte(']');
        },
        .optional => |opt| {
            if (value) |v| {
                try serializePositional(opt.child, v, writer);
            } else {
                try writer.writeAll("null");
            }
        },
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8) {
                // String slice - use JSON string encoding
                try writer.writeByte('"');
                for (value) |c| {
                    switch (c) {
                        '"' => try writer.writeAll("\\\""),
                        '\\' => try writer.writeAll("\\\\"),
                        '\n' => try writer.writeAll("\\n"),
                        '\r' => try writer.writeAll("\\r"),
                        '\t' => try writer.writeAll("\\t"),
                        else => try writer.writeByte(c),
                    }
                }
                try writer.writeByte('"');
            } else if (ptr.size == .slice) {
                // Non-u8 slice (e.g., []SearchContent) - serialize as JSON array
                try writer.writeByte('[');
                for (value, 0..) |item, i| {
                    if (i > 0) try writer.writeByte(',');
                    try serializePositional(ptr.child, item, writer);
                }
                try writer.writeByte(']');
            } else if (ptr.size == .one) {
                // String literal (*const [N]u8 or *const [N:0]u8)
                const child_info = @typeInfo(ptr.child);
                if (child_info == .array and child_info.array.child == u8) {
                    try writer.writeByte('"');
                    for (value) |c| {
                        if (c == 0) break; // Handle null-terminated strings
                        switch (c) {
                            '"' => try writer.writeAll("\\\""),
                            '\\' => try writer.writeAll("\\\\"),
                            '\n' => try writer.writeAll("\\n"),
                            '\r' => try writer.writeAll("\\r"),
                            '\t' => try writer.writeAll("\\t"),
                            else => try writer.writeByte(c),
                        }
                    }
                    try writer.writeByte('"');
                } else {
                    try writer.writeAll("null");
                }
            } else {
                try writer.writeAll("null");
            }
        },
        .array => |arr| {
            try writer.writeByte('[');
            for (value, 0..) |item, i| {
                if (i > 0) try writer.writeByte(',');
                try serializePositional(arr.child, item, writer);
            }
            try writer.writeByte(']');
        },
        .int, .comptime_int => {
            try writer.print("{d}", .{value});
        },
        .float, .comptime_float => {
            try writer.print("{d}", .{value});
        },
        .bool => {
            try writer.writeAll(if (value) "true" else "false");
        },
        .@"enum" => {
            // Serialize enum as integer index for compactness
            try writer.print("{d}", .{@intFromEnum(value)});
        },
        else => {
            try writer.writeAll("null");
        },
    }
}

/// Returns props pointer and JSON serializer function for React components
fn propsSerializerJson(comptime Props: type, allocator: std.mem.Allocator, props: Props) struct {
    ptr: ?*const anyopaque,
    writeFn: ?*const fn (*std.Io.Writer, *const anyopaque) anyerror!void,
} {
    const type_info = @typeInfo(Props);

    if (type_info != .@"struct") return .{ .ptr = null, .writeFn = null };
    if (type_info.@"struct".fields.len == 0) return .{ .ptr = null, .writeFn = null };
    if (!comptime isPropsSerializable(Props)) return .{ .ptr = null, .writeFn = null };

    const props_copy = allocator.create(Props) catch return .{ .ptr = null, .writeFn = null };
    props_copy.* = props;

    return .{
        .ptr = props_copy,
        .writeFn = &struct {
            fn write(writer: *std.Io.Writer, ptr: *const anyopaque) anyerror!void {
                const typed_props: *const Props = @ptrCast(@alignCast(ptr));
                try std.json.Stringify.value(typed_props.*, .{}, writer);
            }
        }.write,
    };
}

fn isPropsSerializable(comptime T: type) bool {
    return isPropsSerializableImpl(T, &.{});
}

fn isPropsSerializableImpl(comptime T: type, comptime visited: []const type) bool {
    // Check if we've already visited this type (recursive type detection)
    for (visited) |v| {
        if (v == T) return true; // Recursive type, assume serializable
    }

    const new_visited = visited ++ [_]type{T};

    const type_info = @typeInfo(T);
    return switch (type_info) {
        .int, .comptime_int, .float, .comptime_float, .bool => true,
        .pointer => |ptr| blk: {
            // Handle slices
            if (ptr.size == .slice) {
                if (ptr.child == u8) break :blk true;
                if (isPropsSerializableImpl(ptr.child, new_visited)) break :blk true;
            }
            if (ptr.size == .one) {
                const child_info = @typeInfo(ptr.child);
                // Check for *const [N]u8 or *const [N:0]u8 (null-terminated string literals)
                if (child_info == .array and child_info.array.child == u8) break :blk true;
            }
            break :blk false;
        },
        .array => |arr| isPropsSerializableImpl(arr.child, new_visited),
        .optional => |opt| isPropsSerializableImpl(opt.child, new_visited),
        .@"struct" => |s| blk: {
            for (s.fields) |field| {
                if (!isPropsSerializableImpl(field.type, new_visited)) break :blk false;
            }
            break :blk true;
        },
        .@"enum" => true,
        else => false,
    };
}

/// Initialize a ZxContext without an allocator
/// The allocator must be provided via @allocator attribute on the parent element
pub fn init() ZxContext {
    return .{ .allocator = std.heap.page_allocator };
}

/// Initialize a ZxContext with an allocator (for backward compatibility with direct API usage)
pub fn allocInit(allocator: std.mem.Allocator) ZxContext {
    return .{ .allocator = allocator };
}

const routing = @import("runtime/core/routing.zig");
const app_module = @import("runtime/server/Server.zig");

pub const routes = @import("zx_meta").routes;
pub const components = @import("zx_meta").components.components;
pub const meta = @import("zx_meta").meta;
pub const info = @import("zx_info");

pub const Allocator = std.mem.Allocator;
pub const App = app_module.Server(void);
pub const Server = app_module.Server;
pub const Edge = @import("runtime/edge/Edge.zig").Edge;
pub const Client = @import("runtime/client/Client.zig");
pub const client = @import("runtime/client/window.zig");
const hydration = @import("runtime/client/hydration.zig");
pub const Signal = Client.reactivity.Signal;
pub const SignalInstance = Client.reactivity.SignalInstance;
pub const Computed = Client.reactivity.Computed;
pub const Effect = Client.reactivity.Effect;
pub const CleanupFn = Client.reactivity.CleanupFn;
pub const effect = Client.reactivity.effect;
pub const effectDeferred = Client.reactivity.effectDeferred;
pub const requestRender = Client.reactivity.requestRender;

pub const PageMethod = enum {
    GET,
    POST,
    PUT,
    DELETE,
    PATCH,
    OPTIONS,
    HEAD,
    CONNECT,
    TRACE,
    ALL,
};
pub const PageOptions = struct {
    pub const StaticParam = struct {
        key: []const u8,
        value: []const u8,
    };

    /// Options for static page generation during `zx export`
    pub const Static = struct {
        params: ?[]const []const StaticParam = null,
        getParams: ?*const fn (std.mem.Allocator) anyerror![]const []const StaticParam = null,
    };

    rendering: ?BuiltinAttribute.Rendering = null,
    caching: BuiltinAttribute.Caching = .none,
    methods: []const PageMethod = &.{.GET},
    static: ?Static = null,
    /// Enable streaming SSR with async components
    streaming: bool = false,
};

pub const LayoutOptions = struct {
    rendering: ?BuiltinAttribute.Rendering = null,
    caching: BuiltinAttribute.Caching = .none,
};
pub const NotFoundOptions = struct {
    rendering: ?BuiltinAttribute.Rendering = null,
    caching: BuiltinAttribute.Caching = .none,
};
pub const ErrorOptions = struct {};
pub const RouteOptions = struct {
    pub const StaticParam = struct {
        key: []const u8,
        value: []const u8,
    };

    pub const Static = struct {
        params: ?[]const []const StaticParam = null,
        getParams: ?*const fn (std.mem.Allocator) anyerror![]const []const StaticParam = null,
    };

    caching: BuiltinAttribute.Caching = .none,
    static: ?Static = null,
};

/// Options for proxy middleware
pub const ProxyOptions = struct {
    /// Whether to continue to the next handler if proxy doesn't handle the request
    pass_through: bool = true,
};

/// Context passed to proxy middleware functions.
/// Use `state.set()` to pass typed data to downstream route/page handlers.
pub const ProxyContext = struct {
    request: Request,
    response: Response,
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,

    //TODO: move these to single _inner ptr
    _aborted: bool = false,
    _state_ptr: ?*const anyopaque = null,

    pub fn init(request: Request, response: Response, allocator: std.mem.Allocator, arena: std.mem.Allocator) ProxyContext {
        return .{
            .request = request,
            .response = response,
            .allocator = allocator,
            .arena = arena,
        };
    }

    /// Set typed state data to be passed to downstream route/page handlers.
    /// (e.g., `zx.RouteCtx(AppCtx, MyState)` or `zx.PageCtx(AppCtx, MyState)`).
    pub fn state(self: *ProxyContext, value: anytype) void {
        const T = @TypeOf(value);
        const ptr = self.arena.create(T) catch return;
        ptr.* = value;
        self._state_ptr = @ptrCast(ptr);
    }

    /// Abort the request chain - no further handlers (proxies, page, route) will be called
    /// Use this when the proxy has fully handled the request (e.g., returned an error response)
    pub fn abort(self: *ProxyContext) void {
        self._aborted = true;
    }

    /// Continue to the next handler in the chain
    /// This is a no-op (chain continues by default), but makes intent explicit
    pub fn next(self: *ProxyContext) void {
        _ = self;
        // No-op - chain continues by default unless abort() is called
    }

    /// Check if the request chain was aborted
    pub fn isAborted(self: *const ProxyContext) bool {
        return self._aborted;
    }
};

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

/// Compute the merged type of two structs for props spreading
/// All fields from both structs are included in the result
pub fn MergedPropsType(comptime BaseType: type, comptime OverrideType: type) type {
    const base_info = @typeInfo(BaseType);
    const override_info = @typeInfo(OverrideType);

    if (base_info != .@"struct" or override_info != .@"struct") {
        @compileError("MergedPropsType expects struct types");
    }

    const base_fields = base_info.@"struct".fields;
    const override_fields = override_info.@"struct".fields;

    // Count unique fields (override fields replace base fields with same name)
    comptime var field_count = base_fields.len;
    inline for (override_fields) |of| {
        comptime var found = false;
        inline for (base_fields) |bf| {
            if (std.mem.eql(u8, bf.name, of.name)) {
                found = true;
                break;
            }
        }
        if (!found) field_count += 1;
    }

    // Build the combined fields array
    comptime var fields: [field_count]std.builtin.Type.StructField = undefined;
    comptime var idx: usize = 0;

    // Add base fields (unless overridden)
    inline for (base_fields) |bf| {
        comptime var overridden = false;
        inline for (override_fields) |of| {
            if (std.mem.eql(u8, bf.name, of.name)) {
                overridden = true;
                break;
            }
        }
        if (overridden) {
            // Use override field's type
            inline for (override_fields) |of| {
                if (std.mem.eql(u8, bf.name, of.name)) {
                    fields[idx] = of;
                    break;
                }
            }
        } else {
            fields[idx] = bf;
        }
        idx += 1;
    }

    // Add new fields from override
    inline for (override_fields) |of| {
        comptime var found = false;
        inline for (base_fields) |bf| {
            if (std.mem.eql(u8, bf.name, of.name)) {
                found = true;
                break;
            }
        }
        if (!found) {
            fields[idx] = of;
            idx += 1;
        }
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

/// Builder returned by ctx.Signal(T) - call .init(initial) to create the signal.
pub fn SignalBuilder(comptime T: type) type {
    return struct {
        const Self = @This();
        _id: u16,

        /// Initialize the signal with an initial value.
        /// Usage: `const count = ctx.Signal(i32).init(0);`
        pub fn init(self: Self, initial: T) SignalInstance(T) {
            return Signal(T).create(self._id, initial);
        }
    };
}

pub fn ComponentCtx(comptime PropsType: type) type {
    return struct {
        const Self = @This();
        props: PropsType,
        allocator: Allocator,
        children: ?Component = null,
        /// Instance ID - automatically injected by Client.zig at runtime
        _id: u16 = 0,

        /// Get a signal builder for this component instance.
        /// Usage: `const count = ctx.Signal(i32).init(ctx.props.initial);`
        pub fn Signal(self: Self, comptime T: type) SignalBuilder(T) {
            return .{ ._id = self._id };
        }
    };
}

pub const ComponentContext = ComponentCtx(void);

pub const EventContext = struct {
    /// The JS event object reference (as a u64 NaN-boxed value)
    event_ref: u64,

    pub fn init(event_ref: u64) EventContext {
        return .{ .event_ref = event_ref };
    }

    /// Get the underlying js.Object for the event
    pub fn getEvent(self: EventContext) client.Event {
        return client.Event.fromRef(self.event_ref);
    }

    /// Get the underlying js.Object with data loaded (value, key, etc)
    pub fn getEventWithData(self: EventContext, allocator: Allocator) client.Event {
        return client.Event.fromRefWithData(allocator, self.event_ref);
    }

    pub fn preventDefault(self: EventContext) void {
        self.getEvent().preventDefault();
    }

    /// Get the input value from event.target.value
    pub fn value(self: EventContext) ?[]const u8 {
        if (platform != .browser) return null;
        const real_js = @import("js");
        const event = self.getEvent();
        const target = event.ref.get(real_js.Object, "target") catch return null;
        return target.getAlloc(real_js.String, client_allocator, "value") catch null;
    }

    /// Get the key from keyboard event
    pub fn key(self: EventContext) ?[]const u8 {
        if (platform != .browser) return null;
        const real_js = @import("js");
        const event = self.getEvent();
        return event.ref.getAlloc(real_js.String, client_allocator, "key") catch null;
    }
};

pub const ActionContext = struct {
    request: Request,
    response: Response,
    allocator: Allocator,
    arena: Allocator,
    action_ref: u64,
    pub fn init(action_ref: u64) ActionContext {
        return .{ .action_ref = action_ref };
    }
};

pub fn ActionResult(comptime T: type) type {
    if (T == void) return void;
    return struct {
        success: bool,
        data: T,
    };
}

pub const EventHandler = *const fn (event: EventContext) void;

pub const BuiltinAttribute = struct {
    pub const Rendering = enum {
        /// Client-side React.js
        react,
        /// Client-side Zig
        client,
        /// Server-side rendering (default)
        server,
        /// Static rendering (pre-render the component/page/layout as static HTML and store in cache/cdn)
        static,

        pub fn from(value: []const u8) Rendering {
            const v = if (std.mem.startsWith(u8, value, ".")) value[1..value.len] else value;
            return std.meta.stringToEnum(Rendering, v) orelse .client;
        }
    };

    pub const Escaping = enum {
        /// HTML escaping (default behavior)
        html,
        /// No escaping; outputs raw HTML. Use with caution for trusted content only.
        none, // no escaping
    };

    pub const Async = enum {
        /// Render synchronously (default)
        sync,
        /// Render asynchronously, stream when ready with inline script replacement
        stream,
    };

    pub const Caching = struct {
        pub const none = Caching{ .seconds = 0 };

        /// The number of seconds to cache the page for
        seconds: u32,
        /// The key to cache the page for
        key: ?[]const u8 = null,

        /// Examples:
        ///
        /// - `10s` → `{ .seconds = 10, .key = null }`
        /// - `5m` → `{ .seconds = 300, .key = null }`
        /// - `1h` → `{ .seconds = 3600, .key = null }`
        /// - `1d` → `{ .seconds = 86400, .key = null }`
        ///
        /// With key:
        /// - `10s:key` → `{ .seconds = 10, .key = "key" }`
        /// - `5m:key` → `{ .seconds = 300, .key = "key" }`
        /// - `1h:key` → `{ .seconds = 3600, .key = "key" }`
        /// - `1d:key` → `{ .seconds = 86400, .key = "key" }`
        pub fn tag(comptime tag_str: []const u8) Caching {
            comptime {
                var num_end: usize = 0;
                while (num_end < tag_str.len) : (num_end += 1) {
                    const c = tag_str[num_end];
                    if (!std.ascii.isDigit(c)) break;
                }
                if (num_end == 0) @compileError("Invalid caching tag '" ++ tag_str ++ "': no number found");

                const num_str = tag_str[0..num_end];
                const rest = tag_str[num_end..];

                var unit_end: usize = 0;
                var key: ?[]const u8 = null;
                for (rest, 0..) |c, i| {
                    if (c == ':') {
                        unit_end = i;
                        key = rest[i + 1 ..];
                        break;
                    }
                } else {
                    unit_end = rest.len;
                }
                const unit_str = rest[0..unit_end];

                const num_value = std.fmt.parseInt(u64, num_str, 10) catch @compileError("Invalid caching number '" ++ num_str ++ "'");
                const unit_value = parseUnit(unit_str);

                const seconds = num_value * unit_value;

                return .{ .seconds = seconds, .key = key };
            }
        }

        fn parseUnit(comptime unit: []const u8) comptime_int {
            if (std.mem.eql(u8, unit, "s") or unit.len == 0) return 1;
            if (std.mem.eql(u8, unit, "m")) return std.time.s_per_min;
            if (std.mem.eql(u8, unit, "h")) return std.time.s_per_hour;
            if (std.mem.eql(u8, unit, "d")) return std.time.s_per_day;
            @compileError("Invalid caching unit '" ++ unit ++ "', supported units: s, m, h, d");
        }
    };
};

const builtin = @import("builtin");
pub const client_allocator = if (builtin.os.tag == .freestanding) std.heap.wasm_allocator else std.heap.page_allocator;
pub const Platform = enum {
    /// Browser environment (WASM)
    browser,
    /// Server environment
    server,

    /// Future - Android environment
    android,
    /// Future - iOS environment
    ios,
    /// Future - macOS environment
    macos,
    /// Future - Windows environment
    windows,
};

/// The platform the code is running on
/// - `browser` if running in a browser environment (WASM)
/// - `server` if running on a server environment
/// - `android` if running on an Android environment
/// - `ios` if running on an iOS environment
/// - `macos` if running on a macOS environment
/// - `windows` if running on a Windows environment
pub const platform: Platform = if (builtin.os.tag == .freestanding) .browser else .server;

pub const Headers = @import("runtime/core/Headers.zig");
pub const Request = @import("runtime/core/Request.zig");
pub const Response = @import("runtime/core/Response.zig");
pub const Fetch = @import("runtime/core/Fetch.zig");
pub const WebSocket = @import("runtime/core/WebSocket.zig");

/// Io determines how fetch operations are executed.
/// - `Io.blocking` - Blocks until complete (server-side)
/// - `Io.wasm(&callback)` - Uses callback when complete (WASM)
pub const Io = Fetch.Io;

/// Perform an HTTP fetch request (works on both browser and server).
///
/// This is a convenience function that delegates to `Fetch.fetch()`.
///
/// **Example:**
/// ```zig
/// var response = try zx.fetch(allocator, "/api/users", .{});
/// defer response.deinit();
///
/// if (response.ok()) {
///     const user = try response.json(User);
///     defer user.deinit();
/// }
/// ```
pub const fetch = Fetch.fetch;

/// Default std_options for zx apps.
/// Re-export this in your main.zig:
/// ```zig
/// pub const std_options = zx.std_options;
/// ```
pub const std_options: std.Options = .{
    .logFn = if (platform == .browser) Client.logFn else std.log.defaultLog,
};
