# Zig Tree-sitter

[![CI][ci]](https://github.com/tree-sitter/zig-tree-sitter/actions/workflows/ci.yml)
[![docs][docs]](https://tree-sitter.github.io/zig-tree-sitter/)

Zig bindings to the [tree-sitter] parsing library.

## Usage

<details>
<summary><code>build.zig</code></summary>

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zig-tree-sitter-usage",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    const tree_sitter = b.dependency("tree_sitter", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("tree-sitter", tree_sitter.module("tree_sitter"));

    const tree_sitter_zig = b.dependency("tree_sitter_zig", .{
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibrary(tree_sitter_zig.artifact("tree-sitter-zig"));

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the example");
    run_step.dependOn(&run_cmd.step);
}
```

</details>

<details open>
<summary><code>src/main.zig</code></summary>

```zig
const std = @import("std");
const ts = @import("tree-sitter");

extern fn tree_sitter_zig() callconv(.c) *ts.Language;

pub fn main() !void {
    // Create a parser for the zig language
    const language = tree_sitter_zig();
    defer language.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(language);

    // Parse some source code and get the root node
    const tree = parser.parseString("pub fn main() !void {}", null);
    defer tree.?.destroy();

    const node = tree.?.rootNode();
    std.debug.assert(std.mem.eql(u8, node.kind(), "source_file"));
    std.debug.assert(node.endPoint().cmp(.{ .row = 0, .column = 22 }) == .eq);

    // Create a query and execute it
    var error_offset: u32 = 0;
    const query = try ts.Query.create(language, "name: (identifier) @name", &error_offset);
    defer query.destroy();

    const cursor = ts.QueryCursor.create();
    defer cursor.destroy();
    cursor.exec(query, node);

    // Get the captured node of the first match
    const match = cursor.nextMatch().?;
    const capture = match.captures[0].node;
    std.debug.assert(std.mem.eql(u8, capture.kind(), "identifier"));
}
```

</details>

[tree-sitter]: https://tree-sitter.github.io/tree-sitter/
[ci]: https://img.shields.io/github/actions/workflow/status/tree-sitter/zig-tree-sitter/ci.yml?logo=github&label=CI
[docs]: https://img.shields.io/github/deployments/tree-sitter/zig-tree-sitter/github-pages?logo=zig&label=API%20Docs
