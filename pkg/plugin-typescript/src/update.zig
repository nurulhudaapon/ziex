const std = @import("std");

/// Native @typescript/typescript-* packages (optionalDependencies of typescript@7).
const platforms = [_][]const u8{
    "aix-ppc64",
    "darwin-arm64",
    "darwin-x64",
    "freebsd-arm64",
    "freebsd-x64",
    "linux-arm",
    "linux-arm64",
    "linux-loong64",
    "linux-mips64el",
    "linux-ppc64",
    "linux-riscv64",
    "linux-s390x",
    "linux-x64",
    "netbsd-arm64",
    "netbsd-x64",
    "openbsd-arm64",
    "openbsd-x64",
    "sunos-x64",
    "win32-arm64",
    "win32-x64",
};

const zon_path = "build.zig.zon";

pub fn main(init: std.process.Init) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const allocator = arena_state.allocator();
    const io = init.io;

    var args = try init.minimal.args.iterateAllocator(allocator);
    defer args.deinit();
    _ = args.next(); // argv0

    const zig_exe = args.next() orelse {
        std.debug.print("usage: update-typescript <zig-exe>\n", .{});
        return error.MissingZigExe;
    };

    const zon_text = try std.Io.Dir.cwd().readFileAlloc(io, zon_path, allocator, .unlimited);
    const version = try parseZonVersion(zon_text);
    std.debug.print("Fetching typescript {s} for {d} platforms...\n", .{ version, platforms.len });

    for (platforms) |plat| {
        const dep_name = try depNameForPlatform(allocator, plat);
        const url = try std.fmt.allocPrint(
            allocator,
            "https://registry.npmjs.org/@typescript/typescript-{s}/-/typescript-{s}-{s}.tgz",
            .{ plat, plat, version },
        );

        std.debug.print("  {s}\n", .{dep_name});
        try runZigFetch(io, allocator, zig_exe, dep_name, url);
    }

    try markTypescriptDepsLazy(io, allocator);
    std.debug.print("Done. typescript {s} pinned in build.zig.zon\n", .{version});
}

fn parseZonVersion(zon_text: []const u8) ![]const u8 {
    const key = ".version";
    const key_idx = std.mem.indexOf(u8, zon_text, key) orelse return error.VersionNotFound;
    const after_key = zon_text[key_idx + key.len ..];
    const eq_idx = std.mem.indexOfScalar(u8, after_key, '=') orelse return error.VersionNotFound;
    var rest = std.mem.trimStart(u8, after_key[eq_idx + 1 ..], " \t\n\r");
    if (rest.len == 0 or rest[0] != '"') return error.VersionNotFound;
    rest = rest[1..];
    const end = std.mem.indexOfScalar(u8, rest, '"') orelse return error.VersionNotFound;
    return rest[0..end];
}

fn depNameForPlatform(allocator: std.mem.Allocator, plat: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(allocator, "typescript_");
    for (plat) |c| {
        try out.append(allocator, if (c == '-') '_' else c);
    }
    return out.toOwnedSlice(allocator);
}

fn runZigFetch(
    io: std.Io,
    allocator: std.mem.Allocator,
    zig_exe: []const u8,
    dep_name: []const u8,
    url: []const u8,
) !void {
    const save_arg = try std.fmt.allocPrint(allocator, "--save={s}", .{dep_name});
    const argv = [_][]const u8{ zig_exe, "fetch", save_arg, url };

    var child = try std.process.spawn(io, .{
        .argv = &argv,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .inherit,
    });
    const term = try child.wait(io);
    const exit_code: u8 = switch (term) {
        .exited => |c| c,
        else => 1,
    };
    if (exit_code != 0) return error.ZigFetchFailed;
}

fn markTypescriptDepsLazy(io: std.Io, allocator: std.mem.Allocator) !void {
    const text = try std.Io.Dir.cwd().readFileAlloc(io, zon_path, allocator, .unlimited);

    var out: std.ArrayList(u8) = .empty;
    try out.ensureTotalCapacity(allocator, text.len + 512);

    var i: usize = 0;
    while (i < text.len) {
        if (std.mem.startsWith(u8, text[i..], ".typescript_")) {
            const block_start = i;
            const name_end = std.mem.indexOfScalar(u8, text[i..], '=') orelse {
                try out.append(allocator, text[i]);
                i += 1;
                continue;
            };
            const after_eq = i + name_end + 1;
            const brace = std.mem.indexOfScalar(u8, text[after_eq..], '{') orelse {
                try out.append(allocator, text[i]);
                i += 1;
                continue;
            };
            const body_start = after_eq + brace;
            const body_end = findMatchingBrace(text, body_start) orelse {
                try out.append(allocator, text[i]);
                i += 1;
                continue;
            };
            const block = text[block_start .. body_end + 1];
            try out.appendSlice(allocator, text[block_start..body_start]);
            if (std.mem.indexOf(u8, block, ".lazy") != null) {
                try out.appendSlice(allocator, text[body_start .. body_end + 1]);
            } else {
                // Trim trailing whitespace/newlines inside the dependency body before injecting .lazy.
                var trimmed_end = body_end;
                while (trimmed_end > body_start and (text[trimmed_end - 1] == ' ' or text[trimmed_end - 1] == '\t' or text[trimmed_end - 1] == '\n' or text[trimmed_end - 1] == '\r')) {
                    trimmed_end -= 1;
                }
                const indent = detectIndentBeforeClose(text, body_end);
                try out.appendSlice(allocator, text[body_start..trimmed_end]);
                try out.append(allocator, '\n');
                try out.appendSlice(allocator, indent);
                try out.appendSlice(allocator, "    .lazy = true,\n");
                try out.appendSlice(allocator, indent);
                try out.append(allocator, '}');
            }
            i = body_end + 1;
            continue;
        }
        try out.append(allocator, text[i]);
        i += 1;
    }

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = zon_path, .data = out.items });
    std.debug.print("Marked all typescript_* dependencies as lazy.\n", .{});
}

fn findMatchingBrace(text: []const u8, open_idx: usize) ?usize {
    if (open_idx >= text.len or text[open_idx] != '{') return null;
    var depth: usize = 0;
    var i = open_idx;
    while (i < text.len) : (i += 1) {
        switch (text[i]) {
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if (depth == 0) return i;
            },
            else => {},
        }
    }
    return null;
}

fn detectIndentBeforeClose(text: []const u8, close_idx: usize) []const u8 {
    var line_start = close_idx;
    while (line_start > 0 and text[line_start - 1] != '\n') : (line_start -= 1) {}
    return text[line_start..close_idx];
}
