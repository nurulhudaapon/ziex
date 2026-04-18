pub fn Page(allocator: zx.Allocator) zx.Component {
    const count = 42;
    const hex_value = 255;
    const percentage = 75;
    const float_value = 3.14;
    const bool_value = true;
    const person: Person = .{
        .name = "John",
        .age = 30,
        .email = "john@example.com",
    };

    // TODO: Add support for pointer to struct array
    // const persons = allocator.alloc(Person, 2) catch unreachable;
    // persons[0] = person;
    // persons[1] = person;

    var _zx = @import("zx").x.allocInit(allocator);
    return _zx.ele(
        .section,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Count: "),
                            _zx.expr(count),
                        },
                    },
                ),
                _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Hex: 0x"),
                            _zx.expr(hex_value),
                        },
                    },
                ),
                _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Percentage: "),
                            _zx.expr(percentage),
                            _zx.txt("%"),
                        },
                    },
                ),
                _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Count: "),
                            _zx.expr(count),
                        },
                    },
                ),
                _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Hex: 0x"),
                            _zx.expr(hex_value),
                        },
                    },
                ),
                _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Percentage: "),
                            _zx.expr(percentage),
                            _zx.txt("%"),
                        },
                    },
                ),
                _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Float: "),
                            _zx.expr(float_value),
                        },
                    },
                ),
                _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Bool: "),
                            _zx.expr(bool_value),
                        },
                    },
                ),
                _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Person: "),
                            _zx.expr(person),
                        },
                    },
                ),
            },
        },
    );
}

const Person = struct {
    name: []const u8,
    age: u32,
    email: []const u8,
};

const zx = @import("zx");
