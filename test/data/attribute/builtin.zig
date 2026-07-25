pub fn Page(allocator: zx.Allocator) zx.Component {
    const a = allocator;
    var _zx = @import("zx").x.allocInit(a, .{ .src = @src() });
    return _zx.ele(
        .section,
        .{
            .allocator = a,
            .children = _zx.chs(.{
                _zx.cmp(
                    ArgToBuiltin,
                    .{ .src = @src() },
                    .{ .name = "ArgToBuiltin" },
                    .{},
                ),
                _zx.cmp(
                    StructToBuiltin,
                    .{ .src = @src() },
                    .{ .name = "StructToBuiltin" },
                    .{},
                ),
            }),
        },
    );
}

fn ArgToBuiltin(arena: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(arena, .{ .src = @src() });
    return _zx.ele(
        .section,
        .{
            .allocator = arena,
        },
    );
}

const Props = struct { c: zx.Allocator };
fn StructToBuiltin(a: zx.Allocator) zx.Component {
    const props = Props{ .c = a };
    var _zx = @import("zx").x.allocInit(props.c, .{ .src = @src() });
    return _zx.ele(
        .section,
        .{
            .allocator = props.c,
        },
    );
}

const zx = @import("zx");
