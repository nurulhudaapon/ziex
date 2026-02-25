pub fn Page(allocator: zx.Allocator) zx.Component {
    const chars = "abcdefg";
    const char = chars[0];

    var _zx = @import("zx").allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                switch (char) {
                    0, 1, 2, 3 => _zx.txt("0 or 1 or 2 or 3"),
                    4...5, 8, 11...13, 15 => _zx.txt("4 to 5 or 8 or 11 to 13 or 15"),
                    'z', 'x' => _zx.txt("z or x"),
                    'a'...'c' => _zx.txt("a to c"),
                    'd'...'f' => _zx.txt("d to f"),
                    else => _zx.txt("other"),
                },
            },
        },
    );
}

const zx = @import("zx");
