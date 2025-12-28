//! ZX - A Zig library for building web applications with JSX-like syntax.
//! This module provides the core component system, rendering engine, and utilities
//! for creating type-safe, high-performance web applications with server-side rendering.
const std = @import("std");
pub const Ast = @import("zx/Ast.zig");
pub const Parse = @import("zx/Parse.zig");

/// Client component rendering type - available on all targets

// HTML Tags
const ElementTag = enum {
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

/// Escape HTML attribute values to prevent XSS attacks
/// Escapes: & < > " '
fn escapeAttributeValueToWriter(writer: *std.Io.Writer, value: []const u8) !void {
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

const ComponentSerializable = struct {
    tag: ?ElementTag = null,
    text: ?[]const u8 = null,
    attributes: ?[]const Element.Attribute = null,
    children: ?[]ComponentSerializable = null,

    pub fn init(allocator: Allocator, component: Component) !ComponentSerializable {
        return switch (component) {
            .text => |text| .{ .text = text },
            .element => |element| blk: {
                const children_serializable = if (element.children) |children| blk2: {
                    const serializable = try allocator.alloc(ComponentSerializable, children.len);
                    for (children, 0..) |child, i| {
                        serializable[i] = try ComponentSerializable.init(allocator, child);
                    }
                    break :blk2 serializable;
                } else null;
                break :blk .{
                    .tag = element.tag,
                    .attributes = element.attributes,
                    .children = children_serializable,
                };
            },
            .component_csr => |component_csr| .{
                .tag = .div,
                .attributes = &.{.{ .name = "id", .value = component_csr.id }},
            },
            .component_fn => |comp_fn| blk: {
                // Resolve component_fn by calling it, then serialize the result
                // This avoids serializing anyopaque fields
                const resolved = comp_fn.call();
                const serialized = try ComponentSerializable.init(allocator, resolved);
                break :blk serialized;
            },
        };
    }

    pub fn initChildren(allocator: Allocator, children: []const Component) ![]ComponentSerializable {
        const children_serializable = try allocator.alloc(ComponentSerializable, children.len);
        for (children, 0..) |child, i| {
            children_serializable[i] = try ComponentSerializable.init(allocator, child);
        }
        return children_serializable;
    }

    pub fn serialize(self: ComponentSerializable, writer: *std.Io.Writer) !void {

        // try std.zon.stringify.serializeArbitraryDepth(
        //     self,
        //     .{
        //         .whitespace = true,
        //         .emit_default_optional_fields = false,
        //     },
        //     writer,
        // );

        try std.json.Stringify.value(
            self,
            .{ .whitespace = .indent_2 },
            writer,
        );
    }
};

pub const Component = union(enum) {
    text: []const u8,
    element: Element,
    component_fn: ComponentFn,
    component_csr: ComponentCsr,

    pub const ComponentCsr = struct {
        name: []const u8,
        path: []const u8,
        id: []const u8,
        props_json: ?[]const u8 = null,
    };

    pub const ComponentFn = struct {
        propsPtr: ?*const anyopaque,
        callFn: *const fn (propsPtr: ?*const anyopaque, allocator: Allocator) Component,
        allocator: Allocator,
        deinitFn: ?*const fn (propsPtr: ?*const anyopaque, allocator: Allocator) void,

        pub fn init(comptime func: anytype, allocator: Allocator, props: anytype) ComponentFn {
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
                fn call(propsPtr: ?*const anyopaque, alloc: Allocator) Component {
                    if (first_is_ctx_ptr) {
                        const CtxType = @typeInfo(FirstPropType).pointer.child;
                        const ctx_ptr: *CtxType = @ptrCast(@alignCast(@constCast(propsPtr orelse @panic("ctx is null"))));
                        return func(ctx_ptr);
                    }
                    if (first_is_allocator and param_count == 1) {
                        return func(alloc);
                    }
                    if (first_is_allocator and param_count == 2) {
                        const SecondPropType = FuncInfo.@"fn".params[1].type.?;
                        const p = propsPtr orelse @panic("propsPtr is null for function with props");
                        const typed_p: *const SecondPropType = @ptrCast(@alignCast(p));
                        return func(alloc, typed_p.*);
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
                .allocator = allocator,
                .deinitFn = Wrapper.deinit,
            };
        }

        pub fn call(self: ComponentFn) Component {
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
            .text => {},
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
                // Free allocated strings
                allocator.free(component_csr.name);
                allocator.free(component_csr.path);
                allocator.free(component_csr.id);
                if (component_csr.props_json) |props_json| {
                    allocator.free(props_json);
                }
            },
        }
    }

    pub fn render(self: Component, writer: *std.Io.Writer) !void {
        try self.internalRender(writer, .{ .escaping = .html, .rendering = .server });
    }

    /// Stream method that renders HTML while collecting elements with 'slot' attribute
    /// Returns an array of Component elements that have a 'slot' attribute
    pub fn stream(self: Component, allocator: std.mem.Allocator, writer: *std.Io.Writer) ![]Component {
        var slots = std.array_list.Managed(Component).init(allocator);
        errdefer slots.deinit();

        try self.internalRender(writer, &slots);
        return slots.toOwnedSlice();
    }

    const RenderInnerOptions = struct {
        slots: ?*std.array_list.Managed(Component) = null,
        escaping: ?BuiltinAttribute.Escaping = .html,
        rendering: ?BuiltinAttribute.Rendering = .server,
    };
    fn internalRender(self: Component, writer: *std.Io.Writer, options: RenderInnerOptions) !void {
        switch (self) {
            .text => |text| {
                try writer.print("{s}", .{text});
            },
            .component_fn => |func| {
                // Lazily invoke the component function and render its result
                const component = func.call();
                try component.internalRender(writer, options);
            },
            .component_csr => |component_csr| {
                try writer.print("<{s} id=\"{s}\"", .{ "div", component_csr.id });
                if (component_csr.props_json) |props_json| {
                    try writer.print(" data-name=\"{s}\" data-props=\"", .{component_csr.name});
                    // Escape JSON for HTML attribute
                    try escapeAttributeValueToWriter(writer, props_json);
                    try writer.print("\"", .{});
                }
                try writer.print(">", .{});
                try writer.print("</{s}>", .{"div"});
            },
            .element => |elem| {
                // Check if this element has a 'slot' attribute and we're collecting slots
                if (options.slots != null) {
                    var has_slot = false;
                    if (elem.attributes) |attributes| {
                        for (attributes) |attribute| {
                            if (std.mem.eql(u8, attribute.name, "slot")) {
                                has_slot = true;
                                break;
                            }
                        }
                    }

                    // If element has 'slot' attribute, accumulate it instead of rendering
                    if (has_slot) {
                        try options.slots.?.append(self);
                        return;
                    }
                }

                // <><div>...</div></> => <div>...</div>
                if (elem.tag == .fragment) {
                    if (elem.children) |children| {
                        for (children) |child| {
                            try child.internalRender(writer, options);
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
                        try writer.print(" {s}", .{attribute.name});
                        if (attribute.value) |value| {
                            try writer.writeAll("=\"");
                            try escapeAttributeValueToWriter(writer, value);
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
                    for (children) |child| {
                        try child.internalRender(writer, options);
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
                const resolved = func.call();
                self.* = resolved;
                // Now search the resolved component
                return self.getElementByName(allocator, tag);
            },
            .text, .component_csr => return null,
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

    pub fn format(
        self: *const Component,
        w: *std.Io.Writer,
    ) error{WriteFailed}!void {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        var serializable = ComponentSerializable.init(allocator, self.*) catch return error.WriteFailed;
        try serializable.serialize(w);
    }
};

pub const Element = struct {
    pub const Attribute = struct {
        name: []const u8,
        value: ?[]const u8 = null,
    };

    tag: ElementTag,
    children: ?[]const Component = null,
    attributes: ?[]const Element.Attribute = null,

    escaping: ?BuiltinAttribute.Escaping = .html,
    rendering: ?BuiltinAttribute.Rendering = .server,
};

const ZxOptions = struct {
    children: ?[]const Component = null,
    attributes: ?[]const Element.Attribute = null,
    allocator: ?std.mem.Allocator = null,
    escaping: ?BuiltinAttribute.Escaping = .html,
    rendering: ?BuiltinAttribute.Rendering = .server,
};

pub fn zx(tag: ElementTag, options: ZxOptions) Component {
    std.debug.print("zx: Tag: {s}, allocator: {any}\n", .{ @tagName(tag), options.allocator });
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

/// Context for creating components with allocator support
const ZxContext = struct {
    allocator: ?std.mem.Allocator = null,

    pub fn getAlloc(self: *ZxContext) std.mem.Allocator {
        return self.allocator orelse @panic("Allocator not set. Please provide @allocator attribute to the parent element.");
    }

    fn escapeHtml(self: *ZxContext, text: []const u8) []const u8 {
        const allocator = self.getAlloc();
        // Use a buffer writer to leverage the shared escaping logic
        var aw = std.io.Writer.Allocating.init(allocator);
        escapeAttributeValueToWriter(&aw.writer, text) catch @panic("OOM");
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
        } };
    }

    pub fn txt(self: *ZxContext, text: []const u8) Component {
        const escaped = self.escapeHtml(text);
        return .{ .text = escaped };
    }

    pub fn expr(self: *ZxContext, val: anytype) Component {
        const T = @TypeOf(val);

        if (T == Component) return val;

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
            // Strings pass through directly
            .pointer => |ptr_info| blk: {
                if (ptr_info.size == .slice and ptr_info.child == u8) {
                    break :blk .{ .name = name, .value = val };
                }
                if (ptr_info.size == .one) {
                    if (@typeInfo(ptr_info.child) == .array) {
                        const Slice = []const std.meta.Elem(ptr_info.child);
                        return self.attr(name, @as(Slice, val));
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

    pub fn cmp(self: *ZxContext, comptime func: anytype, props: anytype) Component {
        const allocator = self.getAlloc();
        const FuncInfo = @typeInfo(@TypeOf(func));
        const param_count = FuncInfo.@"fn".params.len;
        const FirstPropType = FuncInfo.@"fn".params[0].type.?;
        const first_is_ctx_ptr = @typeInfo(FirstPropType) == .pointer and
            @hasField(@typeInfo(FirstPropType).pointer.child, "allocator") and
            @hasField(@typeInfo(FirstPropType).pointer.child, "children");

        // Context-based component or function with props parameter
        if (first_is_ctx_ptr or param_count == 2) {
            const PropsType = if (first_is_ctx_ptr) @TypeOf(props) else FuncInfo.@"fn".params[1].type.?;
            const coerced_props = coerceProps(PropsType, props);
            return .{ .component_fn = Component.ComponentFn.init(func, allocator, coerced_props) };
        } else {
            return .{ .component_fn = Component.ComponentFn.init(func, allocator, props) };
        }
    }

    pub fn client(self: *ZxContext, options: ClientComponentOptions, props: anytype) Component {
        const allocator = self.getAlloc();

        const name_copy = allocator.alloc(u8, options.name.len) catch @panic("OOM");
        @memcpy(name_copy, options.name);
        const path_copy = allocator.alloc(u8, options.path.len) catch @panic("OOM");
        @memcpy(path_copy, options.path);
        const id_copy = allocator.alloc(u8, options.id.len) catch @panic("OOM");
        @memcpy(id_copy, options.id);

        const props_json = std.json.Stringify.valueAlloc(allocator, props, .{}) catch @panic("OOM");

        return .{ .component_csr = .{
            .name = name_copy,
            .path = path_copy,
            .id = id_copy,
            .props_json = props_json,
        } };
    }
};

/// Initialize a ZxContext without an allocator
/// The allocator must be provided via @allocator attribute on the parent element
pub fn init() ZxContext {
    return .{ .allocator = std.heap.page_allocator };
}

/// Initialize a ZxContext with an allocator (for backward compatibility with direct API usage)
pub fn allocInit(allocator: std.mem.Allocator) ZxContext {
    return .{ .allocator = allocator };
}

const routing = @import("routing.zig");

pub const info = @import("zx_info");
pub const Client = @import("client/Client.zig");
pub const App = @import("app.zig").App;

pub const Allocator = std.mem.Allocator;

const PageOptionsStatic = struct {};
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
    rendering: ?BuiltinAttribute.Rendering = null,
    caching: BuiltinAttribute.Caching = .none,
    methods: []const PageMethod = &.{.GET},
    static: ?PageOptionsStatic = null,
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
pub const PageContext = routing.PageContext;
pub const LayoutContext = routing.LayoutContext;
pub const NotFoundContext = routing.NotFoundContext;
pub const ErrorContext = routing.ErrorContext;

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

pub fn ComponentCtx(comptime PropsType: type) type {
    if (PropsType == void) {
        return struct {
            allocator: Allocator,
            children: ?Component = null,
        };
    } else {
        return struct {
            props: PropsType,
            allocator: Allocator,
            children: ?Component = null,
        };
    }
}
pub const ComponentContext = ComponentCtx(void);
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
            return std.meta.stringToEnum(Rendering, v) orelse {
                std.debug.print("Invalid rendering type: {s}\n", .{value});
                return .client;
            };
        }
    };

    pub const Escaping = enum {
        /// HTML escaping (default behavior)
        html,
        /// No escaping; outputs raw HTML. Use with caution for trusted content only.
        none, // no escaping
    };

    pub const Caching = union(enum) {
        none,
        seconds: u32,

        /// Example:
        ///
        /// `5s` -> .{ .seconds = 5 }
        ///
        /// `10m` -> .{ .seconds = 600 }
        ///
        /// `1h` -> .{ .seconds = 3600 }
        ///
        /// `1y` -> .{ .seconds = 31536000 }
        tag: []const u8,

        /// Get caching duration in seconds
        /// Examples: "10s" -> 10, "5m" -> 300, "1h" -> 3600, "1d" -> 86400
        pub fn getSeconds(self: Caching) ?u32 {
            switch (self) {
                .seconds => |seconds| return seconds,
                .tag => |tag| return parseTagRuntime(tag),
                .none => return null,
            }
        }

        /// Comptime version for compile-time validation
        pub fn getSecondsComptime(comptime self: Caching) comptime_int {
            return comptime switch (self) {
                .seconds => |seconds| seconds,
                .tag => |tag| parseTagComptime(tag),
                .none => 0,
            };
        }

        fn parseTagRuntime(tag: []const u8) u32 {
            var num_end: usize = 0;
            while (num_end < tag.len) : (num_end += 1) {
                const c = tag[num_end];
                if (!std.ascii.isDigit(c)) break;
            }
            if (num_end == 0) return 0;

            const num_str = tag[0..num_end];
            const unit_str = tag[num_end..];

            const num_value = std.fmt.parseInt(u32, num_str, 10) catch return 0;
            const unit_value = parseUnitRuntime(unit_str);

            return num_value * unit_value;
        }

        fn parseTagComptime(comptime tag: []const u8) comptime_int {
            comptime {
                var num_end: usize = 0;
                while (num_end < tag.len) : (num_end += 1) {
                    const c = tag[num_end];
                    if (!std.ascii.isDigit(c)) break;
                }
                if (num_end == 0) @compileError("Invalid caching tag '" ++ tag ++ "': no number found");

                const num_str = tag[0..num_end];
                const unit_str = tag[num_end..];

                const num_value = std.fmt.parseInt(u64, num_str, 10) catch @compileError("Invalid caching number '" ++ num_str ++ "'");
                const unit_value = parseUnitComptime(unit_str);

                return num_value * unit_value;
            }
        }

        fn parseUnitRuntime(unit: []const u8) u32 {
            if (std.mem.eql(u8, unit, "s") or unit.len == 0) return 1;
            if (std.mem.eql(u8, unit, "m")) return std.time.s_per_min;
            if (std.mem.eql(u8, unit, "h")) return std.time.s_per_hour;
            if (std.mem.eql(u8, unit, "d")) return std.time.s_per_day;
            return 1; // default to seconds
        }

        fn parseUnitComptime(comptime unit: []const u8) comptime_int {
            if (std.mem.eql(u8, unit, "s") or unit.len == 0) return 1;
            if (std.mem.eql(u8, unit, "m")) return std.time.s_per_min;
            if (std.mem.eql(u8, unit, "h")) return std.time.s_per_hour;
            if (std.mem.eql(u8, unit, "d")) return std.time.s_per_day;
            @compileError("Invalid caching unit '" ++ unit ++ "', supported units: s, m, h, d");
        }
    };
};
const ClientComponentOptions = struct {
    name: []const u8,
    path: []const u8,
    id: []const u8,
};
