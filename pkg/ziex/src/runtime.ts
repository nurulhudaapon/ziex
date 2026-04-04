import { ZxWasiBridge } from "./wasm/wasi";
import { createKVImports, createMemoryKV } from "./kv";
import { createD1Imports } from "./db";
import { createWasiImports, ProcExit, mergeUint8Arrays } from "./wasi";
import type { WASI } from "./wasi";
import type { KVNamespace } from "./kv";
import type { D1Database } from "./db";

/** Minimal Durable Object namespace shape needed for WebSocket routing. */
export type DurableObjectNamespace = {
    idFromName(name: string): unknown;
    get(id: unknown): { fetch(req: Request): Promise<Response> };
};

export type WsState = {
    upgraded: boolean;
    server: WebSocket | null;
    pendingWrites: Uint8Array[];
    messageQueue: Uint8Array[];
    recvResolve: ((bytes: Uint8Array | null) => void) | null;
    /** Resolved when ws_recv is called for the first time (WASM has entered the message loop). */
    _resolveFirstSuspend?: () => void;
    // Optional pub/sub callbacks (used by DO)
    subscribe?: (topic: string) => void;
    unsubscribe?: (topic: string) => void;
    publish?: (topic: string, data: Uint8Array) => number;
    isSubscribed?: (topic: string) => boolean;
};

/** Build the __zx_ws import object for a given connection state. */
export function buildWsImports(
    Suspending: any,
    mem: () => WebAssembly.Memory,
    decoder: TextDecoder,
    ws: WsState,
) {
    const readStr = (ptr: number, len: number) =>
        decoder.decode(new Uint8Array(mem().buffer, ptr, len));

    return {
        ws_upgrade: (): void => { ws.upgraded = true; },
        ws_write: (ptr: number, len: number): void => {
            const data = new Uint8Array(mem().buffer, ptr, len).slice();
            if (!ws.server) {
                ws.pendingWrites.push(data); // buffer until server is set
            } else {
                ws.server.send(data);
            }
        },
        ws_close: (code: number, reason_ptr: number, reason_len: number): void => {
            ws.server?.close(code, decoder.decode(new Uint8Array(mem().buffer, reason_ptr, reason_len)));
        },
        ws_recv: Suspending ? new Suspending(async (buf_ptr: number, buf_max: number): Promise<number> => {
            // Signal that WASM has reached the receive loop (upgrade has happened).
            if (ws._resolveFirstSuspend) {
                const fn = ws._resolveFirstSuspend;
                ws._resolveFirstSuspend = undefined;
                fn();
            }
            const deliver = (bytes: Uint8Array | null): number => {
                if (bytes === null) return -1;
                const n = Math.min(bytes.length, buf_max);
                new Uint8Array(mem().buffer, buf_ptr, n).set(bytes.subarray(0, n));
                return n;
            };
            if (ws.messageQueue.length > 0) return deliver(ws.messageQueue.shift()!);
            return new Promise<number>((resolve) => {
                ws.recvResolve = (bytes) => resolve(deliver(bytes));
            });
        }) : (_buf_ptr: number, _buf_max: number): number => -1,
        // Pub/sub — delegates to optional callbacks (real in DO, no-ops otherwise)
        ws_subscribe: (ptr: number, len: number): void => { ws.subscribe?.(readStr(ptr, len)); },
        ws_unsubscribe: (ptr: number, len: number): void => { ws.unsubscribe?.(readStr(ptr, len)); },
        ws_publish: (topic_ptr: number, topic_len: number, data_ptr: number, data_len: number): number => {
            const topic = readStr(topic_ptr, topic_len);
            const data = new Uint8Array(mem().buffer, data_ptr, data_len).slice();
            return ws.publish?.(topic, data) ?? 0;
        },
        ws_is_subscribed: (ptr: number, len: number): number =>
            ws.isSubscribed?.(readStr(ptr, len)) ? 1 : 0,
    };
}

/** Create WebSocketPair, wire message/close listeners, flush pending writes. */
export function attachWebSocket(ws: WsState): { client: WebSocket } {
    const WebSocketPairCtor = (globalThis as any).WebSocketPair as new () => { 0: WebSocket; 1: WebSocket };
    const pair = new WebSocketPairCtor();
    const client = pair[0];
    const server = pair[1] as WebSocket & { accept(): void };
    ws.server = server;
    server.accept();

    // Flush writes that happened during socket_open (before server was set)
    for (const data of ws.pendingWrites) server.send(data);
    ws.pendingWrites = [];

    server.addEventListener("message", (event: MessageEvent) => {
        const data = typeof event.data === "string"
            ? new TextEncoder().encode(event.data)
            : new Uint8Array(event.data as ArrayBuffer);
        if (ws.recvResolve) {
            const res = ws.recvResolve; ws.recvResolve = null; res(data);
        } else {
            ws.messageQueue.push(data);
        }
    });

    server.addEventListener("close", () => {
        if (ws.recvResolve) {
            const res = ws.recvResolve; ws.recvResolve = null; res(null);
        }
    });

    return { client };
}

/**
 * Build the `__zx_sys` import object.
 * `sleep_ms` pauses WASM under JSPI so buffered stdout chunks reach the client
 * incrementally; falls back to a sync no-op when JSPI is unavailable.
 */
function buildSysImports(jspi: boolean, Suspending: any) {
    return {
        sleep_ms: jspi
            ? new Suspending(async (ms: number) => new Promise<void>(r => setTimeout(r, ms)))
            : (_ms: number) => {},
    };
}

/**
 * Start the WASM module and return a promise that resolves when it exits.
 * Under JSPI the module runs asynchronously with streaming stdout; without
 * JSPI it runs synchronously and buffers all output.
 */
function executeWasm(
    instance: WebAssembly.Instance,
    jspi: boolean,
    Suspending: any,
    wsState: WsState,
): Promise<void> {
    if (!jspi) {
        try {
            (instance.exports._start as Function)();
        } catch (e) {
            if (!(e instanceof ProcExit)) throw e;
        }
        return Promise.resolve();
    }

    // NOTE: no await — start() runs synchronously until the first Suspending
    // call, writing __EDGE_META__ to stderr and the HTML shell to stdout.
    // The runtime streams stdout to the client while WASM is suspended.
    const start = (WebAssembly as any).promising(instance.exports._start as Function);
    return (start() as Promise<void>)
        .catch((e: unknown) => {
            if (e instanceof Error && e.message.startsWith("proc_exit")) return;
            throw e;
        })
        .finally(() => {
            // Unblock any pending ws_recv on exit/error
            if (wsState.recvResolve) {
                const res = wsState.recvResolve;
                wsState.recvResolve = null;
                res(null);
            }
        });
}

/** Parse edge response metadata from stderr output. */
function parseEdgeMeta(stderrText: string): { status: number; headers: Headers; streaming: boolean } {
    const meta = { status: 200, headers: new Headers(), streaming: false };
    const metaPrefix = "__EDGE_META__:";
    const metaLine = stderrText
        .split("\n")
        .find((line) => line.startsWith(metaPrefix));
    if (metaLine) {
        try {
            const parsed = JSON.parse(metaLine.slice(metaPrefix.length));
            if (parsed.status) meta.status = parsed.status;
            if (parsed.streaming === true) meta.streaming = true;
            if (Array.isArray(parsed.headers)) {
                for (const [name, value] of parsed.headers) {
                    meta.headers.append(name, value);
                }
            }
        } catch { }
    }
    return meta;
}

/**
 * Run a WASM module for a single request using JSPI.
 *
 * Pass `kv` as a map of binding names → KV namespaces. The Zig side selects
 * a binding via `zx.kv.scope("name")`; the top-level `zx.kv.*` functions use
 * `"default"`.
 *
 * @example
 * ```ts
 * return run({
 *   request, env, ctx, module,
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
    db: dbBindings,
    imports,
    wasi,
    websocket: doNamespace,
}: {
    request: Request;
    env?: unknown;
    ctx?: { waitUntil(promise: Promise<unknown>): void };
    module: WebAssembly.Module;
    /** KV namespace bindings — `{ default: env.KV, otherName: env.OTHER_KV }` */
    kv?: Record<string, KVNamespace>;
    /** D1 bindings — `{ default: env.DB, analytics: env.ANALYTICS_DB }` */
    db?: Record<string, D1Database>;
    imports?: (mem: () => WebAssembly.Memory) => Record<string, Record<string, unknown>>;
    wasi?: WASI;
    /**
     * Durable Object namespace to use for WebSocket connections.
     * When provided, WebSocket upgrade requests are automatically forwarded to
     * the DO so that pub/sub works across multiple connected clients.
     */
    websocket?: DurableObjectNamespace;
}): Promise<Response> {
    // Route WebSocket upgrades to the Durable Object so that pub/sub works
    // across all connected clients sharing the same DO instance.
    if (doNamespace && request.headers.get("upgrade")?.toLowerCase() === "websocket") {
        const id = doNamespace.idFromName(new URL(request.url).pathname);
        return doNamespace.get(id).fetch(request);
    }

    const stdinData = request.body
        ? new Uint8Array(await request.arrayBuffer())
        : undefined;

    // Stdout chunks are buffered here initially. For streaming responses they
    // are flushed into a TransformStream once we know streaming is requested;
    // for non-streaming responses the array is used directly as the body,
    // avoiding a TransformStream and allowing content-length framing.
    const stdoutChunks: Uint8Array[] = [];
    let streamWriter: WritableStreamDefaultWriter<Uint8Array> | null = null;

    const { wasiImport, setMemory, collectOutput } = createWasiImports({
        request,
        stdinData,
        onStdout: (chunk) => {
            if (streamWriter) void streamWriter.write(chunk);
            else stdoutChunks.push(chunk);
        },
    });

    let wasmMemory: WebAssembly.Memory = null!;
    const mem = () => wasmMemory;

    const bridgeRef: { current: ZxWasiBridge | null } = { current: null };

    const Suspending = (WebAssembly as any).Suspending;
    const jspi = typeof Suspending === 'function';

    const wsState: WsState = {
        upgraded: false,
        server: null,
        pendingWrites: [],
        messageQueue: [],
        recvResolve: null,
    };

    const instance = new WebAssembly.Instance(module, {
        wasi_snapshot_preview1: { ...wasi?.wasiImport, ...wasiImport },
        __zx_sys: buildSysImports(jspi, Suspending),
        __zx_ws: buildWsImports(jspi ? Suspending : null, mem, new TextDecoder(), wsState),
        __zx_kv: createKVImports(kvBindings ?? { default: createMemoryKV() }, mem),
        __zx_db: createD1Imports(dbBindings ?? {}, mem),
        ...(imports ? imports(mem) : {}),
        ...ZxWasiBridge.createImportObject(bridgeRef),
    } as WebAssembly.Imports);

    wasmMemory = instance.exports.memory as WebAssembly.Memory;
    setMemory(wasmMemory);
    bridgeRef.current = new ZxWasiBridge(instance.exports);

    const wasmPromise = executeWasm(instance, jspi, Suspending, wsState);

    // After start(), WASM has run synchronously until its first Suspending call.
    // For WebSocket routes, that first suspension is ws_recv (after the upgrade
    // call in the Route handler), so wsState.upgraded is already true here.
    if (wsState.upgraded) {
        const server = attachWebSocket(wsState);
        // Keep the Worker alive while WASM processes the WebSocket message loop.
        ctx?.waitUntil(wasmPromise);
        return new Response(null, { status: 101, webSocket: server.client } as ResponseInit);
    }

    const { stderrText: earlyStderrText } = collectOutput();
    const earlyMeta = parseEdgeMeta(earlyStderrText);

    if (earlyMeta.streaming) {
        // Page opted into streaming (zx.PageOptions{ .streaming = true }) —
        // pipe stdout incrementally to the client as WASM yields via sleep_ms.
        const { readable, writable } = new TransformStream<Uint8Array, Uint8Array>();
        streamWriter = writable.getWriter();
        // Flush any chunks written during the synchronous startup phase.
        for (const chunk of stdoutChunks) void streamWriter.write(chunk);
        stdoutChunks.length = 0;
        void wasmPromise.finally(() => streamWriter?.close());
        return new Response(readable, { status: earlyMeta.status, headers: earlyMeta.headers });
    }

    await wasmPromise;
    const { stderrText } = collectOutput();
    const meta = parseEdgeMeta(stderrText);
    const body = mergeUint8Arrays(stdoutChunks);
    meta.headers.delete('transfer-encoding');
    if (!meta.headers.has('content-length')) meta.headers.set('content-length', String(body.byteLength));
    return new Response(body.buffer as ArrayBuffer, { status: meta.status, headers: meta.headers });
}
