pub fn Page(allocator: zx.Allocator) zx.Component {
    const user_name = "Alice & Bob";
    const html_content = "<script>alert('XSS')</script>";
    const unsafe_html = "<span>Test</span>";

    var _zx = @import("zx").x.allocInit(allocator);
    return _zx.ele(
        .main,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.ele(
                    .section,
                    .{
                        .children = &.{
                            _zx.ele(
                                .p,
                                .{
                                    .children = &.{
                                        _zx.txt("User: "),
                                        _zx.expr(user_name),
                                    },
                                },
                            ),
                            _zx.ele(
                                .p,
                                .{
                                    .children = &.{
                                        _zx.txt("Safe HTML: "),
                                        _zx.expr(html_content),
                                    },
                                },
                            ),
                            _zx.ele(
                                .p,
                                .{
                                    .escaping = .html,
                                    .children = &.{
                                        _zx.txt("Unsafe HTML: "),
                                        _zx.expr(unsafe_html),
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

const zx = @import("zx");
