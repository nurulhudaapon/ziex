pub fn Page(allocator: zx.Allocator) zx.Component {
    const a = allocator;
    var _zx = @import("zx").allocInit(a);
    return _zx.ele(
        .section,
        .{
            .allocator = a,
            .children = &.{
                _zx.cmp(
                    ArgToBuiltin,
                    .{ .name = "ArgToBuiltin" },
                    .{},
                ),
                _zx.cmp(
                    StructToBuiltin,
                    .{ .name = "StructToBuiltin" },
                    .{},
                ),
            },
        },
    );
}

fn ArgToBuiltin(arena: zx.Allocator) zx.Component {
    var _zx = @import("zx").allocInit(arena);
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
    var _zx = @import("zx").allocInit(props.c);
    return _zx.ele(
        .section,
        .{
            .allocator = props.c,
        },
    );
}

const zx = @import("zx");
