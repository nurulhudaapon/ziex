pub fn Page(allocator: zx.Allocator) zx.Component {
    // Test values for different types
    const string_val = "hello";
    const int_val: i32 = 42;
    const float_val: f32 = 3.14;
    const bool_true = true;
    const bool_false = false;
    const optional_val: ?[]const u8 = "present";
    const optional_null: ?[]const u8 = null;
    const enum_val = InputType.text;

    var _zx = @import("zx").x.allocInit(allocator);
    return _zx.ele(
        .form,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("type", "text"),
                            _zx.attr("data-string", string_val),
                        }),
                    },
                ),
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("type", "number"),
                            _zx.attr("value", int_val),
                        }),
                    },
                ),
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("type", "range"),
                            _zx.attr("step", float_val),
                        }),
                    },
                ),
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("type", "checkbox"),
                            _zx.attr("disabled", bool_true),
                        }),
                    },
                ),
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("type", "checkbox"),
                            _zx.attr("disabled", bool_false),
                        }),
                    },
                ),
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("type", "text"),
                            _zx.attr("data-user", optional_val),
                        }),
                    },
                ),
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("type", "text"),
                            _zx.attr("data-user", optional_null),
                        }),
                    },
                ),
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr("type", enum_val),
                        }),
                    },
                ),
            },
        },
    );
}

const InputType = enum {
    text,
    number,
    checkbox,
};

const zx = @import("zx");
