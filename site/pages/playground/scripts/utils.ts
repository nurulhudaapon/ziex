import { untar } from "@andrewbranch/untar.js";
import { Directory, File, ConsoleStdout, wasi as wasi_defs } from "@bjorn3/browser_wasi_shim";

export async function fetchWithCache(url: string): Promise<Response> {
    const cache = await caches.open("ziex-pg-v0.1.0-dev.678");
    let response = await cache.match(url);
    if (!response) {
        response = await fetch(url);
        if (response.ok) {
            await cache.put(url, response.clone());
        }
    } else {
        response = response.clone();
    }
    return response;
}

let _cachedZigRoot: TreeNode | null = null;
export async function getLatestZigArchive() {
    if (_cachedZigRoot) return convert(_cachedZigRoot);

    const response = await fetchWithCache("/assets/playground/zig.tar.gz");
    let arrayBuffer = await response.arrayBuffer();
    const magicNumber = new Uint8Array(arrayBuffer).slice(0, 2);
    if (magicNumber[0] == 0x1F && magicNumber[1] == 0x8B) { // gzip
        const ds = new DecompressionStream("gzip");
        const response = new Response(new Response(arrayBuffer).body!.pipeThrough(ds));
        arrayBuffer = await response.arrayBuffer();
    } else {
        // already decompressed
    }
    const entries = untar(arrayBuffer);

    let root: TreeNode = new Map();

    for (const e of entries) {
        if (!e.filename.startsWith("lib/")) continue;
        const path = e.filename.slice("lib/".length);
        const splitPath = path.split("/");

        let c = root;
        for (const segment of splitPath.slice(0, -1)) {
            if (!c.has(segment)) {
                c.set(segment, new Map());
            }
            c = c.get(segment) as TreeNode;
        }


        c.set(splitPath[splitPath.length - 1], e.fileData);
    }

    _cachedZigRoot = root;
    return convert(root);
}

let _cachedZxRoot: TreeNode | null = null;
export async function getZxArchive() {
    if (_cachedZxRoot) return convert(_cachedZxRoot);

    const response = await fetchWithCache("/assets/playground/zx.tar.gz");
    let arrayBuffer = await response.arrayBuffer();
    const magicNumber = new Uint8Array(arrayBuffer).slice(0, 2);
    if (magicNumber[0] == 0x1F && magicNumber[1] == 0x8B) { // gzip
        const ds = new DecompressionStream("gzip");
        const response = new Response(new Response(arrayBuffer).body!.pipeThrough(ds));
        arrayBuffer = await response.arrayBuffer();
    } else {
        // already decompressed
    }
    const entries = untar(arrayBuffer);

    let root: TreeNode = new Map();
    // const includedDirs = ['src', 'pkg', 'vendor', 'src', ''];

    for (const e of entries) {
        // if (!e.filename.startsWith("lib/")) continue;
        const path = e.filename;
        // const path = e.filename.slice("lib/".length);
        const splitPath = path.split("/");

        let c = root;
        for (const segment of splitPath.slice(0, -1)) {
            if (!c.has(segment)) {
                c.set(segment, new Map());
            }
            c = c.get(segment) as TreeNode;
        }


        c.set(splitPath[splitPath.length - 1], e.fileData);
    }

    _cachedZxRoot = root;
    return convert(root);
}

type TreeNode = Map<string, TreeNode | Uint8Array>;

function convert(node: TreeNode): Directory {
    return new Directory(
        [...node.entries()].map(([key, value]) => {
            if (value instanceof Uint8Array) {
                return [key, new File(value)];
            } else {
                return [key, convert(value)];
            }
        })
    )
}

export function stderrOutput(): ConsoleStdout {
    const dec = new TextDecoder("utf-8", { fatal: false });
    const stderr = new ConsoleStdout((buffer) => {
        postMessage({ stderr: dec.decode(buffer, { stream: true }) });
    });
    stderr.fd_pwrite = (data, offset) => {
        return { ret: wasi_defs.ERRNO_SPIPE, nwritten: 0 };
    }
    return stderr;
}

export function stdoutOutput(): ConsoleStdout {
    const dec = new TextDecoder("utf-8", { fatal: false });
    const stdout = new ConsoleStdout((buffer) => {
        postMessage({ stdout: dec.decode(buffer, { stream: true }) });
    });
    stdout.fd_pwrite = (data, offset) => {
        return { ret: wasi_defs.ERRNO_SPIPE, nwritten: 0 };
    }
    return stdout;
}

export function previewOutput(): ConsoleStdout {
    const dec = new TextDecoder("utf-8", { fatal: false });
    const preview = new ConsoleStdout((buffer) => {
        postMessage({ preview: dec.decode(buffer, { stream: true }) });
    });
    preview.fd_pwrite = (data, offset) => {
        return { ret: wasi_defs.ERRNO_SPIPE, nwritten: 0 };
    }
    return preview;
}
