import { ZxBridge } from "../wasm";
import { createKVImports } from "./kv";

class ProcExit extends Error {
    constructor(public readonly code: number) {
        super(`proc_exit(${code})`);
    }
}

function createWasiImports({
    request,
    stdinData,
}: {
    request: Request;
    stdinData?: Uint8Array;
}) {
    const encoder = new TextEncoder();
    const decoder = new TextDecoder();

    // Build args the same way prepare() does, prefixed with a dummy argv[0].
    const url = new URL(request.url);
    const argStrings: string[] = [
        "wasm",
        "--pathname", url.pathname,
        "--method", request.method,
        "--search", url.search,
    ];
    for (const name of FORWARDED_HEADERS) {
        const value = request.headers.get(name);
        if (value) argStrings.push("--header", `${name}:${value}`);
    }

    // Null-terminated encoded args and total buffer size
    const encodedArgs = argStrings.map((a) => encoder.encode(a + "\0"));
    const argBufSize = encodedArgs.reduce((s, a) => s + a.length, 0);

    // WASM memory — set after instantiation
    let wasmMemory: WebAssembly.Memory = null!;
    const setMemory = (m: WebAssembly.Memory) => { wasmMemory = m; };

    const stdoutChunks: Uint8Array[] = [];
    const stderrChunks: Uint8Array[] = [];
    let stdinOffset = 0;

    function v() { return new DataView(wasmMemory.buffer); }
    function m() { return new Uint8Array(wasmMemory.buffer); }

    const wasiImport = {
        args_sizes_get(argc_ptr: number, argv_buf_size_ptr: number): number {
            v().setUint32(argc_ptr, encodedArgs.length, true);
            v().setUint32(argv_buf_size_ptr, argBufSize, true);
            return 0;
        },
        args_get(argv_ptr: number, argv_buf_ptr: number): number {
            const dv = v(); const mem = m();
            let offset = argv_buf_ptr;
            for (const arg of encodedArgs) {
                dv.setUint32(argv_ptr, offset, true);
                mem.set(arg, offset);
                argv_ptr += 4;
                offset += arg.length;
            }
            return 0;
        },
        environ_sizes_get(count_ptr: number, buf_size_ptr: number): number {
            v().setUint32(count_ptr, 0, true);
            v().setUint32(buf_size_ptr, 0, true);
            return 0;
        },
        environ_get(_environ_ptr: number, _environ_buf_ptr: number): number {
            return 0;
        },
        fd_write(fd: number, iovs_ptr: number, iovs_len: number, nwritten_ptr: number): number {
            const dv = v(); const mem = m();
            let written = 0;
            for (let i = 0; i < iovs_len; i++) {
                const buf_ptr = dv.getUint32(iovs_ptr + i * 8, true);
                const buf_len = dv.getUint32(iovs_ptr + i * 8 + 4, true);
                const chunk = mem.slice(buf_ptr, buf_ptr + buf_len);
                if (fd === 1) stdoutChunks.push(chunk);
                else if (fd === 2) stderrChunks.push(chunk);
                written += buf_len;
            }
            dv.setUint32(nwritten_ptr, written, true);
            return 0;
        },
        fd_read(fd: number, iovs_ptr: number, iovs_len: number, nread_ptr: number): number {
            const dv = v(); const mem = m();
            const stdin = stdinData ?? new Uint8Array(0);
            let totalRead = 0;
            for (let i = 0; i < iovs_len; i++) {
                const buf_ptr = dv.getUint32(iovs_ptr + i * 8, true);
                const buf_len = dv.getUint32(iovs_ptr + i * 8 + 4, true);
                if (fd === 0 && stdinOffset < stdin.length) {
                    const toRead = Math.min(buf_len, stdin.length - stdinOffset);
                    mem.set(stdin.subarray(stdinOffset, stdinOffset + toRead), buf_ptr);
                    stdinOffset += toRead;
                    totalRead += toRead;
                }
            }
            dv.setUint32(nread_ptr, totalRead, true);
            return 0;
        },
        fd_fdstat_get(_fd: number, fdstat_ptr: number): number {
            const dv = v();
            dv.setUint8(fdstat_ptr, 2);                         // fs_filetype: regular_file
            dv.setUint8(fdstat_ptr + 1, 0);                     // padding
            dv.setUint16(fdstat_ptr + 2, 0, true);              // fs_flags
            dv.setUint32(fdstat_ptr + 4, 0, true);              // padding
            dv.setBigUint64(fdstat_ptr + 8, 0n, true);          // fs_rights_base
            dv.setBigUint64(fdstat_ptr + 16, 0n, true);         // fs_rights_inheriting
            return 0;
        },
        fd_prestat_get(_fd: number, _bufptr: number): number {
            return 8; // WASI_EBADF — no preopened directories
        },
        fd_prestat_dir_name(_fd: number, _path: number, _path_len: number): number {
            return 8; // WASI_EBADF
        },
        fd_close(_fd: number): number { return 0; },
        fd_pread(_fd: number, _iovs: number, _iovs_len: number, _offset: bigint, nread_ptr: number): number {
            v().setUint32(nread_ptr, 0, true);
            return 0;
        },
        fd_pwrite(_fd: number, _iovs: number, _iovs_len: number, _offset: bigint, nwritten_ptr: number): number {
            v().setUint32(nwritten_ptr, 0, true);
            return 0;
        },
        fd_filestat_get(_fd: number, filestat_ptr: number): number {
            // filestat: dev(8) ino(8) filetype(1) pad(7) nlink(8) size(8) atim(8) mtim(8) ctim(8) = 64 bytes
            const dv = v();
            dv.setBigUint64(filestat_ptr, 0n, true);        // dev
            dv.setBigUint64(filestat_ptr + 8, 0n, true);    // ino
            dv.setUint8(filestat_ptr + 16, 2);              // filetype: regular_file
            dv.setBigUint64(filestat_ptr + 24, 1n, true);   // nlink
            dv.setBigUint64(filestat_ptr + 32, 0n, true);   // size
            dv.setBigUint64(filestat_ptr + 40, 0n, true);   // atim
            dv.setBigUint64(filestat_ptr + 48, 0n, true);   // mtim
            dv.setBigUint64(filestat_ptr + 56, 0n, true);   // ctim
            return 0;
        },
        fd_seek(_fd: number, _offset: bigint, _whence: number, newoffset_ptr: number): number {
            v().setBigInt64(newoffset_ptr, 0n, true);
            return 0;
        },
        proc_exit(code: number): never {
            throw new ProcExit(code);
        },
        sched_yield(): number { return 0; },
        clock_time_get(_id: number, _precision: bigint, time_ptr: number): number {
            v().setBigUint64(time_ptr, BigInt(Date.now()) * 1_000_000n, true);
            return 0;
        },
        random_get(buf_ptr: number, buf_len: number): number {
            crypto.getRandomValues(new Uint8Array(wasmMemory.buffer, buf_ptr, buf_len));
            return 0;
        },
        path_open(_fd: number, _dirflags: number, _path: number, _path_len: number, _oflags: number, _rights_base: bigint, _rights_inheriting: bigint, _fdflags: number, opened_fd_ptr: number): number {
            v().setInt32(opened_fd_ptr, -1, true);
            return 76; // WASI_ENOTCAPABLE
        },
        path_create_directory(_fd: number, _path: number, _path_len: number): number { return 76; },
        path_unlink_file(_fd: number, _path: number, _path_len: number): number { return 76; },
        path_remove_directory(_fd: number, _path: number, _path_len: number): number { return 76; },
        path_rename(_fd: number, _old_path: number, _old_path_len: number, _new_fd: number, _new_path: number, _new_path_len: number): number { return 76; },
        path_filestat_get(_fd: number, _flags: number, _path: number, _path_len: number, filestat_ptr: number): number {
            // zero out the 64-byte filestat struct
            new Uint8Array(wasmMemory.buffer, filestat_ptr, 64).fill(0);
            return 76;
        },
        path_readlink(_fd: number, _path: number, _path_len: number, _buf: number, _buf_len: number, nread_ptr: number): number {
            v().setUint32(nread_ptr, 0, true);
            return 76;
        },
        fd_readdir(_fd: number, _buf: number, _buf_len: number, _cookie: bigint, bufused_ptr: number): number {
            v().setUint32(bufused_ptr, 0, true);
            return 76;
        },
    };

    function collectOutput(): { stdout: Uint8Array; stderrText: string } {
        return {
            stdout: mergeUint8Arrays(stdoutChunks),
            stderrText: decoder.decode(mergeUint8Arrays(stderrChunks)),
        };
    }

    return { wasiImport, setMemory, collectOutput };
}

/**
 * Build a `Response` from the output collected by `createWasiImports`.
 * Parses `__EDGE_META__` from stderrText for status and headers.
 */
function buildResponse({
    stdout,
    stderrText,
}: {
    stdout: Uint8Array;
    stderrText: string;
}): Response {
    const meta = parseEdgeMeta(stderrText);
    return new Response(stdout.buffer as ArrayBuffer, {
        status: meta.status,
        headers: meta.headers,
    });
}

/**
 * Run a WASM module for a single request using JSPI.
 *
 * Pass `kv` as a map of binding names → KV namespaces.  The Zig side selects
 * a binding via `zx.kv.scope("name")`; the top-level `zx.kv.*` functions use
 * `"default"`.
 *
 * @example
 * ```ts
 * return worker.run({
 *   request, env, ctx, wasmModule,
 *   kv: { default: env.KV, users: env.USERS_KV },
 * });
 * ```
 */
export async function run({
    request,
    env,
    ctx,
    module,
    kv: kvBindings,
    imports,
    wasi,
}: {
    request: Request;
    env?: unknown;
    ctx?: unknown;
    module: WebAssembly.Module;
    /** KV namespace bindings — `{ default: env.KV, otherName: env.OTHER_KV }` */
    kv?: Record<string, import("./kv").KVNamespace>;
    imports?: (mem: () => WebAssembly.Memory) => Record<string, Record<string, unknown>>;
    wasi?: WASI;
}): Promise<Response> {
    const stdinData = request.body
        ? new Uint8Array(await request.arrayBuffer())
        : undefined;

    const { wasiImport, setMemory, collectOutput } = createWasiImports({ request, stdinData });

    let wasmMemory: WebAssembly.Memory = null!;
    const mem = () => wasmMemory;

    const bridgeRef: { current: ZxBridge | null } = { current: null };
    const bridgeImports = ZxBridge.createImportObject(bridgeRef);

    const instance = new WebAssembly.Instance(module, {
        wasi_snapshot_preview1: {...wasi?.wasiImport, ...wasiImport},
        ...(kvBindings ? { __zx_kv: createKVImports(kvBindings, mem) } : {}),
        ...(imports ? imports(mem) : {}),
        ...bridgeImports,
    } as WebAssembly.Imports);

    wasmMemory = instance.exports.memory as WebAssembly.Memory;
    setMemory(wasmMemory);
    const bridge = new ZxBridge(instance.exports);
    bridgeRef.current = bridge;

    const start = (WebAssembly as any).promising(instance.exports._start as Function);
    try {
        await start();
    } catch (e) {
        if (!(e instanceof Error) || !e.message.startsWith("proc_exit")) throw e;
    }

    return buildResponse(collectOutput());
}

// ---------------------------------------------------------------------------
// Original workers-wasi path (kept for backwards compatibility)
// ---------------------------------------------------------------------------

/** Headers to forward from the incoming request to the WASI module */
const FORWARDED_HEADERS = [
    "content-type",
    "accept",
    "authorization",
    "cookie",
    "user-agent",
    "referer",
    "x-forwarded-for",
    "x-forwarded-proto",
    "x-real-ip",
];

/** Parse edge response metadata from stderr output */
function parseEdgeMeta(stderrText: string): {
    status: number;
    headers: Headers;
} {
    const meta = { status: 200, headers: new Headers() };
    const metaPrefix = "__EDGE_META__:";
    const metaLine = stderrText
        .split("\n")
        .find((line) => line.startsWith(metaPrefix));
    if (metaLine) {
        try {
            const parsed = JSON.parse(metaLine.slice(metaPrefix.length));
            if (parsed.status) meta.status = parsed.status;
            if (Array.isArray(parsed.headers)) {
                for (const [name, value] of parsed.headers) {
                    meta.headers.append(name, value);
                }
            }
        } catch { }
    }
    return meta;
}

function mergeUint8Arrays(arrays: Uint8Array[]): Uint8Array {
    const totalLen = arrays.reduce((sum, arr) => sum + arr.length, 0);
    const result = new Uint8Array(totalLen);
    let offset = 0;
    for (const arr of arrays) {
        result.set(arr, offset);
        offset += arr.length;
    }
    return result;
}

async function collectStream(
    readable: ReadableStream<Uint8Array>,
    chunks: Uint8Array[],
) {
    const reader = readable.getReader();
    while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        if (value) chunks.push(value);
    }
}

export function prepare({
    request,
    env,
    ctx,
}: {
    request: Request;
    env: unknown;
    ctx: unknown;
}) {
    const stdout = new TransformStream();
    const stderr = new TransformStream();

    const url = new URL(request.url);

    const args: string[] = [
        "--pathname",
        url.pathname,
        "--method",
        request.method,
        "--search",
        url.search,
    ];

    for (const name of FORWARDED_HEADERS) {
        const value = request.headers.get(name);
        if (value) {
            args.push("--header", `${name}:${value}`);
        }
    }

    const stdin: ReadableStream<Uint8Array> | undefined =
        request.body ?? undefined;

    return { args, stdout, stderr, stdin };
}

export async function respond({
    exec,
    stdout,
    stderr,
}: {
    exec: Promise<number | undefined>;
    stdout: TransformStream;
    stderr: TransformStream | ReadableStream<Uint8Array>;
}): Promise<Response> {
    const stdoutChunks: Uint8Array[] = [];
    const stderrChunks: Uint8Array[] = [];

    const stderrReadable = stderr instanceof ReadableStream ? stderr : stderr.readable;

    await Promise.all([
        exec,
        collectStream(stdout.readable, stdoutChunks),
        collectStream(stderrReadable, stderrChunks),
    ]);

    const stderrText = new TextDecoder().decode(mergeUint8Arrays(stderrChunks));
    const meta = parseEdgeMeta(stderrText);

    return new Response(mergeUint8Arrays(stdoutChunks).buffer as ArrayBuffer, {
        status: meta.status,
        headers: meta.headers,
    });
}


type WASI = {
    args?: Array<string>;
    env?: Array<string>;
    fds?: Array<unknown>;
    inst?: {
        exports: {
            memory: WebAssembly.Memory;
        };
    };
    wasiImport:Record<string, Function>| {
        [key: string]: (...args: Array<any>) => unknown;
        
    };
    start(instance: {
        exports: {
            memory: WebAssembly.Memory;
            _start: () => unknown;
        };
    }): number;
    initialize?(instance: {
        exports: {
            memory: WebAssembly.Memory;
            _initialize?: () => unknown;
        };
    }): void;
}