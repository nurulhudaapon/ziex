pub fn Page(allocator: zx.Allocator) zx.Component {
    const name = "Alice";
    const count = 5;
    const item = "apple";

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
                            _zx.txt("Hello "),
                            _zx.expr(name),
                            _zx.txt(", you have "),
                            _zx.expr(count),
                            _zx.expr(item),
                            _zx.txt("s in your cart."),
                        },
                    },
                ),
                _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Welcome back, "),
                            _zx.expr(name),
                            _zx.txt("! Your order #"),
                            _zx.expr(count),
                            _zx.txt(" is ready."),
                        },
                    },
                ),
                _zx.ele(
                    .span,
                    .{
                        .children = &.{
                            _zx.txt("Item: "),
                            _zx.expr(item),
                            _zx.txt(" (qty: "),
                            _zx.expr(count),
                            _zx.txt(")"),
                        },
                    },
                ),
            },
        },
    );
}

const zx = @import("zx");
