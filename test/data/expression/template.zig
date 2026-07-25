pub fn Page(allocator: zx.Allocator) zx.Component {
    const count = 42;
    const name = "John";

    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .section,
        .{
            .allocator = allocator,
            .attributes = _zx.attrs(.{
                _zx.attrf("class", "test-{s} {s}", .{
                    _zx.attrv(count),
                    _zx.attrv(getThemeClass(.dark)),
                }),
                _zx.attrf("data-name", "person-{s}", .{
                    _zx.attrv(name),
                }),
                _zx.attrf("id", "test", .{}),
                _zx.attr(@src(), "data-normal", name),
                _zx.attr(@src(), "data-text", "{text}"),
                _zx.attr(@src(), "data-t", "`{text}`"),
            }),
            .children = _zx.chs(.{
                _zx.ele(
                    .p,
                    .{
                        .children = _zx.chs(.{
                            _zx.txt("My name is "),
                            _zx.expr(name),
                        }),
                    },
                ),
                _zx.cmp(
                    Component,
                    .{ .src = @src() },
                    .{ .name = "Component" },
                    .{ .text = _zx.propf("hello {s}", .{_zx.propv(count)}), .name = _zx.propf("test {s} {s} more-text", .{ _zx.propv(name), _zx.propv(getThemeClass(.dark)) }) },
                ),
            }),
        },
    );
}

fn Component(ctx: *zx.ComponentCtx(struct {
    text: []const u8,
    name: []const u8,
})) zx.Component {
    var _zx = @import("zx").x.allocInit(ctx.allocator, .{ .src = @src() });
    return _zx.ele(
        .div,
        .{
            .allocator = ctx.allocator,
            .children = _zx.chs(.{
                _zx.ele(
                    .p,
                    .{
                        .children = _zx.chs(.{
                            _zx.expr(ctx.props.text),
                        }),
                    },
                ),
                _zx.ele(
                    .p,
                    .{
                        .children = _zx.chs(.{
                            _zx.expr(ctx.props.name),
                        }),
                    },
                ),
            }),
        },
    );
}

const Theme = enum { light, dark };
fn getThemeClass(theme: Theme) []const u8 {
    return switch (theme) {
        .light => "theme-light",
        .dark => "theme-dark",
    };
}

const zx = @import("zx");
