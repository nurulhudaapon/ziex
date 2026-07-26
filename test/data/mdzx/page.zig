const zx = @import("zx");

pub const meta = .{
    .title = "MDZX Fixture",
};

pub const options: zx.PageOptions = .{};

var ctx: zx.PageContext = undefined;

pub fn Page(c: zx.PageContext) zx.Component {
    ctx = c;
    return zx.mdzx.page(@This(), c);
}

pub fn render(allocator: @import("zx").Allocator) @import("zx").Component {
    return (<div @allocator={allocator}>
        <h1>Headers</h1>
        <p>Fixture page for MDZX.</p>
    </div>);
}
