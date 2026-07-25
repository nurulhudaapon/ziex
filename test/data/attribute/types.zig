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

    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .form,
        .{
            .allocator = allocator,
            .children = _zx.chs(.{
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr(@src(), "type", "text"),
                            _zx.attr(@src(), "data-string", string_val),
                        }),
                    },
                ),
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr(@src(), "type", "number"),
                            _zx.attr(@src(), "value", int_val),
                        }),
                    },
                ),
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr(@src(), "type", "range"),
                            _zx.attr(@src(), "step", float_val),
                        }),
                    },
                ),
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr(@src(), "type", "checkbox"),
                            _zx.attr(@src(), "disabled", bool_true),
                        }),
                    },
                ),
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr(@src(), "type", "checkbox"),
                            _zx.attr(@src(), "disabled", bool_false),
                        }),
                    },
                ),
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr(@src(), "type", "text"),
                            _zx.attr(@src(), "data-user", optional_val),
                        }),
                    },
                ),
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr(@src(), "type", "text"),
                            _zx.attr(@src(), "data-user", optional_null),
                        }),
                    },
                ),
                _zx.ele(
                    .input,
                    .{
                        .attributes = _zx.attrs(.{
                            _zx.attr(@src(), "type", enum_val),
                        }),
                    },
                ),
            }),
        },
    );
}

const InputType = enum {
    text,
    number,
    checkbox,
};

const zx = @import("zx");
