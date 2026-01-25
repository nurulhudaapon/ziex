pub fn Page(ctx: zx.PageContext) zx.Component {
    var _zx = zx.allocInit(ctx.arena);
    return _zx.ele(
        .div,
        .{
            .allocator = ctx.arena,
            .attributes = _zx.attrs(.{
                _zx.attr("class", "todo-container"),
            }),
            .children = &.{
                _zx.cmp(
                    TodoApp,
                    .{ .client = .{ .name = "TodoApp", .id = "cb50044" } },
                    .{},
                ),
            },
        },
    );
}

const Todo = struct { id: u32, text: []const u8, completed: bool };
pub fn TodoApp(allocator: zx.Allocator) zx.Component {
    initTodos(todos_allocator);
    if (builtin.cpu.arch != .wasm32) resetTodosForSSR(todos_allocator);

    var _zx = zx.allocInit(allocator);
    return _zx.ele(
        .div,
        .{
            .allocator = allocator,
            .attributes = _zx.attrs(.{
                _zx.attr("class", "todo-app"),
            }),
            .children = &.{
                _zx.ele(
                    .div,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("class", "todo-header"),
                        }),
                        .children = &.{
                            _zx.ele(
                                .h1,
                                .{
                                    .attributes = _zx.attrs(.{
                                        _zx.attr("class", "todo-title"),
                                    }),
                                    .children = &.{
                                        _zx.txt("ZX + WASM"),
                                    },
                                },
                            ),
                            _zx.ele(
                                .p,
                                .{
                                    .attributes = _zx.attrs(.{
                                        _zx.attr("class", "todo-subtitle"),
                                    }),
                                    .children = &.{
                                        _zx.txt("A demo todo app built with ZX Client Side Rendering"),
                                    },
                                },
                            ),
                        },
                    },
                ),
                _zx.ele(
                    .form,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("class", "todo-input-section"),
                            _zx.attr("onsubmit", addTodo),
                        }),
                        .children = &.{
                            _zx.ele(
                                .input,
                                .{
                                    .attributes = _zx.attrs(.{
                                        _zx.attr("type", "text"),
                                        _zx.attr("class", "todo-input"),
                                        _zx.attr("id", "todo-input"),
                                        _zx.attr("placeholder", "Add a new todo..."),
                                        _zx.attr("required", ""),
                                    }),
                                },
                            ),
                            _zx.ele(
                                .button,
                                .{
                                    .attributes = _zx.attrs(.{
                                        _zx.attr("class", "todo-add-btn"),
                                        _zx.attr("type", "submit"),
                                    }),
                                    .children = &.{
                                        _zx.txt("Add"),
                                    },
                                },
                            ),
                        },
                    },
                ),
                _zx.ele(
                    .div,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("class", "todo-stats"),
                        }),
                        .children = &.{
                            _zx.ele(
                                .span,
                                .{
                                    .attributes = _zx.attrs(.{
                                        _zx.attr("class", "todo-stat"),
                                    }),
                                    .children = &.{
                                        _zx.ele(
                                            .strong,
                                            .{
                                                .children = &.{
                                                    _zx.expr(todos.items.len),
                                                },
                                            },
                                        ),
                                        _zx.txt(" total"),
                                    },
                                },
                            ),
                            _zx.ele(
                                .span,
                                .{
                                    .attributes = _zx.attrs(.{
                                        _zx.attr("class", "todo-stat-divider"),
                                    }),
                                    .children = &.{
                                        _zx.txt("•"),
                                    },
                                },
                            ),
                            _zx.ele(
                                .span,
                                .{
                                    .attributes = _zx.attrs(.{
                                        _zx.attr("class", "todo-stat"),
                                    }),
                                    .children = &.{
                                        _zx.ele(
                                            .strong,
                                            .{
                                                .children = &.{
                                                    _zx.expr(countCompleted()),
                                                },
                                            },
                                        ),
                                        _zx.txt(" done"),
                                    },
                                },
                            ),
                            _zx.ele(
                                .span,
                                .{
                                    .attributes = _zx.attrs(.{
                                        _zx.attr("class", "todo-stat-divider"),
                                    }),
                                    .children = &.{
                                        _zx.txt("•"),
                                    },
                                },
                            ),
                            _zx.ele(
                                .span,
                                .{
                                    .attributes = _zx.attrs(.{
                                        _zx.attr("class", "todo-stat"),
                                    }),
                                    .children = &.{
                                        _zx.ele(
                                            .strong,
                                            .{
                                                .children = &.{
                                                    _zx.expr(todos.items.len - countCompleted()),
                                                },
                                            },
                                        ),
                                        _zx.txt(" left"),
                                    },
                                },
                            ),
                            _zx.ele(
                                .button,
                                .{
                                    .attributes = _zx.attrs(.{
                                        _zx.attr("class", "todo-clear-btn"),
                                        _zx.attr("onclick", clearTodos),
                                    }),
                                    .children = &.{
                                        _zx.txt("Clear All"),
                                    },
                                },
                            ),
                        },
                    },
                ),
                _zx.ele(
                    .ul,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("class", "todo-list"),
                        }),
                        .children = &.{
                            _zx_for_blk_0: {
                                const __zx_children_0 = _zx.getAlloc().alloc(zx.Component, todos.items.len) catch unreachable;
                                for (todos.items, 0..) |todo, _zx_i_0| {
                                    __zx_children_0[_zx_i_0] = _zx.cmp(
                                        TodoItem,
                                        .{},
                                        .{ .id = todo.id, .text = todo.text, .completed = todo.completed },
                                    );
                                }
                                break :_zx_for_blk_0 _zx.ele(.fragment, .{ .children = __zx_children_0 });
                            },
                        },
                    },
                ),
            },
        },
    );
}

fn TodoItem(ctx: *zx.ComponentCtx(struct { id: u32, text: []const u8, completed: bool })) zx.Component {
    const class = if (ctx.props.completed) "todo-item todo-item-completed" else "todo-item";
    const key = ctx.props.id;
    const value = ctx.props.id;

    var _zx = zx.allocInit(ctx.allocator);
    return _zx.ele(
        .li,
        .{
            .allocator = ctx.allocator,
            .attributes = _zx.attrs(.{
                _zx.attr("class", class),
                _zx.attr("key", key),
            }),
            .children = &.{
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("type", "button"),
                            _zx.attr("class", "todo-checkbox"),
                            _zx.attr("value", value),
                            _zx.attr("onclick", toggleTodo),
                        }),
                    },
                ),
                _zx.ele(
                    .span,
                    .{
                        .children = &.{
                            _zx.expr(ctx.props.text),
                        },
                    },
                ),
                _zx.ele(
                    .button,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("class", "todo-delete-btn"),
                            _zx.attr("value", value),
                            _zx.attr("onclick", deleteTodo),
                        }),
                        .children = &.{
                            _zx.txt("×"),
                        },
                    },
                ),
            },
        },
    );
}

const initial_todos = [_]Todo{
    .{ .id = 1, .text = "Build a fast web app with ZX", .completed = true },
    .{ .id = 2, .text = "Implement server-side rendering", .completed = true },
    .{ .id = 3, .text = "Implement client-side rendering", .completed = false },
};
var next_todo_id: u32 = 4; // Start after initial todos (1, 2, 3)
var initialized: bool = false;
var todos = std.ArrayList(Todo).empty;
var todos_allocator: std.mem.Allocator = if (builtin.cpu.arch == .wasm32) std.heap.wasm_allocator else std.heap.page_allocator;

fn initTodos(allocator: zx.Allocator) void {
    if (initialized) return;
    initialized = true;
    todos_allocator = allocator;
    todos.appendSlice(allocator, &initial_todos) catch @panic("OOM");
}

fn resetTodosForSSR(allocator: zx.Allocator) void {
    todos = std.ArrayList(Todo).empty;
    todos_allocator = allocator;
    todos.appendSlice(allocator, &initial_todos) catch @panic("OOM");
}

fn addTodo(ctx: zx.EventContext) void {
    ctx.preventDefault();
    if (comptime builtin.cpu.arch != .wasm32) return;

    const document = zx.client.Document.init(todos_allocator);
    const input = document.getElementById("todo-input") catch return;

    const text = input.ref.getAlloc(js.String, todos_allocator, "value") catch return;
    if (text.len == 0) return;

    const id = next_todo_id;
    next_todo_id += 1;
    todos.append(todos_allocator, .{ .id = id, .text = text, .completed = false }) catch @panic("OOM");
    input.ref.set("value", js.string("")) catch return;
    zx.requestRender();
}

fn handleInputChange(ctx: zx.EventContext) void {
    const event = ctx.getEvent();
    defer event.deinit();
    const target = event.getTarget() orelse return;
    defer target.deinit();
    const value = target.getAlloc(js.String, todos_allocator, "value") catch return;

    const id = next_todo_id;
    next_todo_id += 1;
    todos.append(todos_allocator, .{ .id = id, .text = value, .completed = false }) catch @panic("OOM");
}
fn toggleTodo(ctx: zx.EventContext) void {
    if (comptime builtin.cpu.arch != .wasm32) return;

    const event = ctx.getEvent();
    defer event.deinit();
    var id: ?u32 = null;
    if (event.getTarget()) |target| {
        defer target.deinit();
        if (target.getAlloc(js.String, todos_allocator, "value") catch null) |v| {
            id = std.fmt.parseInt(u32, v, 10) catch null;
        }
    }

    for (todos.items) |*todo| {
        if (todo.id == id) {
            todo.completed = !todo.completed;
            break;
        }
    }
    zx.requestRender();
}

fn clearTodos(_: zx.EventContext) void {
    todos.clearRetainingCapacity();
    zx.requestRender();
}

fn deleteTodo(ctx: zx.EventContext) void {
    if (comptime builtin.cpu.arch != .wasm32) return;

    const event = ctx.getEvent();
    defer event.deinit();
    var id: ?u32 = null;
    if (event.getTarget()) |target| {
        defer target.deinit();
        if (target.getAlloc(js.String, todos_allocator, "value") catch null) |v| {
            id = std.fmt.parseInt(u32, v, 10) catch null;
        }
    }

    for (todos.items, 0..) |todo, i| {
        if (todo.id == id) {
            _ = todos.orderedRemove(i);
            break;
        }
    }
    zx.requestRender();
}

fn countCompleted() u32 {
    var count: u32 = 0;
    for (todos.items) |todo| {
        if (todo.completed) count += 1;
    }
    return count;
}

const zx = @import("zx");
const std = @import("std");
const builtin = @import("builtin");
const client = zx.client;
const js = zx.Client.js;
