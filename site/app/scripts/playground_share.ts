export type PlaygroundFilesMap = Record<string, string>;

export const DEFAULT_PLAYGROUND_MAIN = `const std = @import("std");
const zx = @import("zx");
const pg = @import("Playground.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var aw = std.Io.Writer.Allocating.init(allocator);

    const type_info = @typeInfo(pg);
    const decls = type_info.@"struct".decls;

    inline for (decls) |decl| {
        const component = resolveComponent(allocator, decl.name);
        try component.render(&aw.writer, .{});
    }

    try std.fs.File.stdout().writeAll(aw.written());
}

fn resolveComponent(allocator: zx.Allocator, comptime field_name: []const u8) zx.Component {
    const Cmp = @field(pg, field_name);

    const FnInfo = @typeInfo(@TypeOf(Cmp)).@"fn";
    const param_count = FnInfo.params.len;
    const FirstParam = FnInfo.params[0].type.?;

    if (param_count == 1 and @typeInfo(FirstParam) == .pointer and
        @hasField(@typeInfo(FirstParam).pointer.child, "allocator") and
        @hasField(@typeInfo(FirstParam).pointer.child, "children"))
    {
        const ctx = allocator.create(@typeInfo(FirstParam).pointer.child) catch @panic("OOM");
        ctx.* = .{ .allocator = allocator, .props = {} };
        return Cmp(ctx);
    }

    if (param_count == 1 and FirstParam == zx.Allocator) {
        return Cmp(allocator);
    }
}
`;

export const DEFAULT_PLAYGROUND_STYLE = `body {
    background: #111;
    color: #fff;
    display: grid;
    place-items: center;
    height: 90vh;
}
`;

const ZX_IMPORT_LINE = 'const zx = @import("zx");';

function ensureTopLevelZxImport(code: string): string {
    const hasTopLevelImport = code
        .split(/\r?\n/)
        .some((line) => /^const\s+zx\s*=\s*@import\("zx"\);\s*$/.test(line));

    if (hasTopLevelImport) {
        return code;
    }

    const normalized = code.replace(/\s+$/, "");
    return `${normalized}\n\n${ZX_IMPORT_LINE}`;
}

export function createDocsSnippetFiles(code: string, filename = "Playground.zx"): PlaygroundFilesMap {
    void filename;
    return {
        "Playground.zx": ensureTopLevelZxImport(code),
    };
}

export async function encodeFilesToQuery(filesMap: PlaygroundFilesMap): Promise<string> {
    const json = JSON.stringify(filesMap);
    const stream = new Blob([json]).stream().pipeThrough(new CompressionStream("deflate"));
    const buffer = await new Response(stream).arrayBuffer();

    let binString = "";
    const bytes = new Uint8Array(buffer);
    const CHUNK_SIZE = 0x8000;
    for (let i = 0; i < bytes.length; i += CHUNK_SIZE) {
        binString += String.fromCharCode.apply(null, Array.from(bytes.subarray(i, i + CHUNK_SIZE)));
    }

    const b64 = btoa(binString);
    return b64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function decodeFilesFromQuery(query: string): Promise<PlaygroundFilesMap | null> {
    try {
        let b64 = query.replace(/-/g, "+").replace(/_/g, "/");
        while (b64.length % 4) {
            b64 += "=";
        }

        const binString = atob(b64);
        const bytes = Uint8Array.from(binString, (m) => m.codePointAt(0) ?? 0);
        const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("deflate"));
        const text = await new Response(stream).text();

        return JSON.parse(text) as PlaygroundFilesMap;
    } catch {
        return null;
    }
}

export async function createPlaygroundShareUrl(filesMap: PlaygroundFilesMap, baseUrl: string): Promise<string> {
    const encoded = await encodeFilesToQuery(filesMap);
    return `${baseUrl}#data=${encoded}`;
}