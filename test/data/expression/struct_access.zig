pub fn Page(allocator: zx.Allocator) zx.Component {
    const user = User{ .name = "Alice", .age = 25 };
    const product = Product{ .title = "Book", .price = 29.99 };

    var _zx = @import("zx").x.allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Name: "),
                            _zx.expr(user.name),
                        },
                    },
                ),
                _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Age: "),
                            _zx.expr(user.age),
                        },
                    },
                ),
                _zx.ele(
                    .div,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("class", "product"),
                        }),
                        .children = &.{
                            _zx.ele(
                                .h2,
                                .{
                                    .children = &.{
                                        _zx.expr(product.title),
                                    },
                                },
                            ),
                            _zx.ele(
                                .span,
                                .{
                                    .children = &.{
                                        _zx.txt("Price: $"),
                                        _zx.expr(product.price),
                                    },
                                },
                            ),
                        },
                    },
                ),
            },
        },
    );
}

const User = struct { name: []const u8, age: u32 };
const Product = struct { title: []const u8, price: f64 };

const zx = @import("zx");
