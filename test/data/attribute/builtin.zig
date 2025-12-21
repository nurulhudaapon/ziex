pub fn Page(allocator: zx.Allocator) zx.Component {
    const a = allocator;
    var _zx = zx.initWithAllocator(a);
    return _zx.zx(
        .section,
        .{
            .allocator = a,
            .children = &.{
                _zx.lazy(ArgToBuiltin, .{}),
                _zx.lazy(StructToBuiltin, .{}),
            },
        },
    );
}

fn ArgToBuiltin(arena: zx.Allocator) zx.Component {
    var _zx = zx.initWithAllocator(arena);
    return _zx.zx(
        .section,
        .{
            .allocator = arena,
        },
    );
}

const Props = struct { c: zx.Allocator };
fn StructToBuiltin(a: zx.Allocator) zx.Component {
    const props = Props{ .c = a };
    var _zx = zx.initWithAllocator(props.c);
    return _zx.zx(
        .section,
        .{
            .allocator = props.c,
        },
    );
}

const zx = @import("zx");
