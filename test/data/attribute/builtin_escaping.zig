pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .section,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                _zx.ele(
                    .style,
                    .{
                        .children = _zx.chs(.{
                            _zx.expr(
                                \\div {
                                \\    background-color: red;
                                \\    padding: 10px;
                                \\    border-radius: 5px;
                                \\    border: 1px solid black;
                                \\    margin: 10px;
                                \\    width: 100px;
                                \\    height: 100px;
                                \\    display: flex;
                                \\    justify-content: center;
                                \\    align-items: center;
                                \\    font-size: 16px;
                                \\    font-weight: bold;
                                \\    color: white;
                                \\    text-align: center;
                                \\    text-decoration: none;
                                \\    text-transform: uppercase;
                                \\    letter-spacing: 1px;
                                \\}
                            ),
                        }),
                    },
                ),
                _zx.ele(
                    .script,
                    .{
                        .escaping = .none,
                        .children = _zx.chs(.{
                            _zx.expr(
                                \\ import { data } from "./data.js";
                                \\const data = { name: "test" };
                                \\console.log(data);
                            ),
                        }),
                    },
                ),
                _zx.ele(
                    .pre,
                    .{
                        .escaping = .none,
                        .children = _zx.chs(.{
                            _zx.txt("                \n"),
                            _zx.expr(
                                \\<h1>name</h1>
                            ),
                            _zx.txt("            "),
                        }),
                    },
                ),
                _zx.ele(
                    .pre,
                    .{
                        .escaping = .html,
                        .attributes = _zx.attrs(.{
                            _zx.attr(@src(), "class", "bold"),
                            _zx.attr(@src(), "class", "italic"),
                        }),
                        .children = _zx.chs(.{
                            _zx.txt("                \n"),
                            _zx.expr(
                                \\<h1>name</h1>
                            ),
                            _zx.txt("            "),
                        }),
                    },
                ),
            }),
        },
    );
}

const zx = @import("zx");
