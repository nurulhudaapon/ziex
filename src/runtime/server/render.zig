const std = @import("std");
const zx = @import("../../root.zig");
const registry = @import("registry.zig");

/// Set by handler.zig before calling render/stream so that any ActionContext
/// handlers encountered during the render pass are registered for this route.
pub var current_route_path: ?[]const u8 = null;

pub const streaming_bootstrap_script =
    \\<script>window.$ZX=function(id,html){var t=document.getElementById('__ZX_S-'+id);if(t){var d=document.createElement('div');d.innerHTML=html;while(d.firstChild)t.parentNode.insertBefore(d.firstChild,t);t.remove();}}</script>
;

/// Async component collected during streaming
pub const AsyncComponent = struct {
    id: u32,
    component: zx.Component,

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
pub fn stream(self: zx.Component, allocator: std.mem.Allocator, writer: *std.Io.Writer) ![]AsyncComponent {
    var async_components = std.array_list.Managed(AsyncComponent).init(allocator);
    errdefer async_components.deinit();

    var counter: u32 = 0;
    try renderInner(self, writer, .{
        .escaping = .html,
        .rendering = .server,
        .async_components = &async_components,
        .async_counter = &counter,
    });
    return async_components.toOwnedSlice();
}

pub const RenderInnerOptions = struct {
    escaping: ?zx.BuiltinAttribute.Escaping = .html,
    rendering: ?zx.BuiltinAttribute.Rendering = .server,
    async_components: ?*std.array_list.Managed(AsyncComponent) = null,
    async_counter: ?*u32 = null,
};

pub fn render(self: zx.Component, writer: *std.Io.Writer) !void {
    try renderInner(self, writer, .{ .escaping = .html, .rendering = .server });
}

pub fn renderInner(self: zx.Component, writer: *std.Io.Writer, options: RenderInnerOptions) !void {
    switch (self) {
        .none => {
            // Render nothing
        },
        .text => |text| {
            if (options.escaping == .none) {
                try zx.util.html.unescape(writer, text);
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
                        if (zx.cache.get(key)) |cached_html| {
                            try writer.writeAll(cached_html);
                            return;
                        }

                        // Render to buffer for caching
                        var buf_writer = std.Io.Writer.Allocating.init(func.allocator);
                        const component = try func.call();
                        try renderInner(component, &buf_writer.writer, options);

                        const rendered = buf_writer.written();
                        zx.cache.put(key, rendered, caching.seconds);

                        // Write to actual output
                        try writer.writeAll(rendered);
                        return;
                    }
                }
            }

            // No caching or cache miss - render directly
            const component = try func.call();
            try renderInner(component, writer, options);
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
                try renderInner(children.*, writer, options);
            }

            // End comment marker: <!--/$id-->
            try writer.print("<!--/${s}-->", .{component_csr.id});
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
                    try renderInner(fallback.*, writer, .{
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
                        try renderInner(child, writer, options);
                    }
                }
                return;
            }

            // Otherwise, render normally
            // Opening tag
            try writer.print("<{s}", .{@tagName(elem.tag)});

            const is_self_closing = elem.tag.isSelf();
            const is_no_closing = elem.tag.isVoid();

            // Handle attributes
            var has_action_handler = false;
            if (elem.attributes) |attributes| {
                var has_method = false;

                for (attributes) |attribute| {
                    if (attribute.handler) |handler| {
                        // Register ActionContext handlers so the server can dispatch them.
                        if (handler.action_fn) |action_fn| {
                            if (current_route_path) |rp| {
                                registry.register(rp, action_fn);
                            }
                            has_action_handler = true;
                        }

                        if (handler.server_event_fn) |action_fn| {
                            if (current_route_path) |rp| {
                                registry.registerEvent(rp, handler.handler_id, action_fn);
                            }
                        }
                    } else {
                        if (std.mem.eql(u8, attribute.name, "method")) {
                            has_method = true;
                        }
                        // defaultValue is a DOM property; the HTML attribute equivalent is "value"
                        const attr_name = if (std.mem.eql(u8, attribute.name, "defaultValue")) "value" else attribute.name;
                        try writer.print(" {s}", .{attr_name});
                    }
                    if (attribute.value) |value| {
                        try writer.writeAll("=\"");
                        try zx.util.html.escapeAttr(writer, value);
                        try writer.writeAll("\"");
                    }
                }

                // Mimic Next.js: auto-inject method="post" enctype="multipart/form-data"
                // on form elements with an action handler
                if (elem.tag == .form and has_action_handler and !has_method) {
                    try writer.writeAll(" method=\"post\" enctype=\"multipart/form-data\"");
                }
            }

            // Closing bracket
            if (!is_self_closing or is_no_closing) {
                try writer.print(">", .{});
            } else {
                try writer.print(" />", .{});
            }

            // Inject hidden field so no-JS form submissions can be identified as action requests
            if (elem.tag == .form and has_action_handler) {
                try writer.writeAll("<input type=\"hidden\" name=\"__$action\" value=\"1\">");
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
                    try renderInner(child, writer, child_options);
                }
            }

            // Closing tag
            if (!is_self_closing and !is_no_closing) {
                try writer.print("</{s}>", .{@tagName(elem.tag)});
            }
        },
    }
}
