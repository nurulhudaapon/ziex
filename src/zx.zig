const std = @import("std");

const zx = @import("root.zig");
const prp = @import("props.zig");

const ElementTag = zx.ElementTag;
const Element = zx.Element;
const Allocator = std.mem.Allocator;
const BuiltinAttribute = zx.BuiltinAttribute;
const Component = zx.Component;
const ElementAttribute = zx.Element.Attribute;
const reactivity = zx.client.reactivity;

const platform = zx.platform;
//TODO: Do not escape ahead of time, remove escaping from this place
const escapHtmlTextNode = zx.util.html.escapeText;

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
    /// Component name used for devtools / debugging.
    /// Pass `null` (or omit) in release builds to reduce binary size.
    name: ?[]const u8 = null,
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

pub fn x(tag: ElementTag, options: ZxOptions) Component {
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
pub const ZxContext = struct {
    allocator: ?std.mem.Allocator = null,
    style_registry: ?*std.StringArrayHashMap([]const u8) = null,

    pub fn getAlloc(self: *ZxContext) std.mem.Allocator {
        return self.allocator orelse @panic("Allocator not set. Please provide @allocator attribute to the parent element.");
    }

    /// Check if a Style has any pseudo-states or media queries
    fn hasSelectors(style_obj: zx.Style) bool {
        const fields = std.meta.fields(zx.Style);
        inline for (fields) |f| {
            if (f.type == ?*const zx.Style) {
                if (@field(style_obj, f.name) != null) return true;
            }
        }
        return false;
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
        defer aw.deinit();
        escapHtmlTextNode(&aw.writer, text) catch @panic("OOM");
        return allocator.dupe(u8, aw.written()) catch @panic("OOM");
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

        if (comptime isStatePointer(T)) return self.expr(val.get());

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

        if (comptime isStatePointer(T)) {
            return self.attr(name, val.get());
        }

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
                        const fn_params = @typeInfo(ptr_info.child).@"fn".params;
                        const takes_ptr = fn_params.len == 1 and
                            @typeInfo(fn_params[0].type.?) == .pointer;
                        const handler = if (takes_ptr)
                            zx.EventHandler.runtimePtr(val)
                        else
                            zx.EventHandler.runtime(val);
                        break :blk .{ .name = name, .handler = handler };
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
                .handler = if (comptime std.mem.eql(u8, name, "action"))
                    zx.EventHandler.action(val)
                else
                    zx.EventHandler.wrap(val),
            },
            // Pre-built event handlers
            .@"struct" => if (T == zx.EventHandler) .{
                .name = name,
                .handler = val,
            } else if (T == zx.Style) blk: {
                if (comptime std.mem.eql(u8, name, "style")) {
                    if (hasSelectors(val)) {
                        // We need a deterministic hash of the style
                        // For now, let's just use the formatted string as the key
                        const style_str = self.printf("{f}", .{val});
                        
                        // Register style if registry exists
                        if (self.style_registry) |reg| {
                            const hash = std.hash.Wyhash.hash(0, style_str);
                            const class_name = self.printf("zx-{x}", .{hash});
                            
                            if (!reg.contains(class_name)) {
                                // Important: We store the Style object itself or its string representation.
                                // For now, storing the string is easier for the final flush.
                                reg.put(class_name, style_str) catch @panic("OOM");
                            }
                            
                            // Return class attribute instead of style
                            break :blk .{
                                .name = "class",
                                .value = class_name,
                            };
                        }
                    }
                }
                break :blk .{
                    .name = name,
                    .value = self.printf("{f}", .{val}),
                };
            } else @compileError("Unsupported struct type for attribute: " ++ @typeName(T)),

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
    pub fn propsM(_: *ZxContext, base: anytype, overrides: anytype) prp.MergedPropsType(@TypeOf(base), @TypeOf(overrides)) {
        const BaseType = @TypeOf(base);
        const OverrideType = @TypeOf(overrides);
        const ResultType = prp.MergedPropsType(BaseType, OverrideType);

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

    pub fn cmp(self: *ZxContext, comptime func: anytype, options: ZxOptions, props: anytype) Component {
        const allocator = self.getAlloc();

        const FuncInfo = @typeInfo(@TypeOf(func));
        const param_count = FuncInfo.@"fn".params.len;
        const FirstPropType = FuncInfo.@"fn".params[0].type.?;
        const first_is_ctx_ptr = @typeInfo(FirstPropType) == .pointer and
            @hasField(@typeInfo(FirstPropType).pointer.child, "allocator") and
            @hasField(@typeInfo(FirstPropType).pointer.child, "children");

        const name = options.name orelse "";
        // Context-based component or function with props parameter
        var comp_fn = if (first_is_ctx_ptr or param_count == 2) blk: {
            const PropsType = if (first_is_ctx_ptr) @TypeOf(props) else FuncInfo.@"fn".params[1].type.?;
            const coerced_props = prp.coerceProps(PropsType, props);
            break :blk Component.ComponentFn.init(func, name, allocator, coerced_props);
        } else blk: {
            break :blk Component.ComponentFn.init(func, name, allocator, props);
        };

        // Apply builtin attributes from options
        comp_fn.async_mode = options.async orelse .sync;
        comp_fn.fallback = options.fallback;
        comp_fn.caching = options.caching;

        // If client option is set, return a client component (for @rendering={.client})
        // Render the component on the server for SSR, then hydrate on client.
        // On Browser (already on the client), skip the CSR wrapper — just render
        // the component directly as a component_fn.
        if (options.client != null and zx.platform == .browser) {
            return .{ .component_fn = comp_fn };
        }
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
                            const full_props = prp.coerceProps(FullPropsType, props);
                            break :blk prp.propsSerializer(FullPropsType, allocator, full_props);
                        }
                    }
                } else if (param_count == 2) {
                    const FullPropsType = FuncInfo.@"fn".params[1].type.?;
                    if (@typeInfo(FullPropsType) == .@"struct") {
                        const full_props = prp.coerceProps(FullPropsType, props);
                        break :blk prp.propsSerializer(FullPropsType, allocator, full_props);
                    }
                }
                // Fallback: serialize the props as-is
                break :blk prp.propsSerializer(@TypeOf(props), allocator, props);
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
        const props_data = prp.propsSerializerJson(Props, allocator, props);

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

fn isStatePointer(comptime PT: type) bool {
    const type_info = @typeInfo(PT);

    if (type_info != .pointer) return false;
    if (type_info.pointer.size != .one) return false;

    const CT = type_info.pointer.child;

    if (@typeInfo(CT) != .@"struct") return false;

    return @hasField(CT, "value") and
        @hasField(CT, "component_id") and
        @hasDecl(CT, "get") and
        @hasDecl(CT, "set") and
        @hasDecl(CT, "update");
}
