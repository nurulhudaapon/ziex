import { ZxBridge } from "../../wasm";
import { createFetchImports } from "../../runtime/fetch";
import { createKVImports } from "../../runtime/kv/extern";
import { createDbImports } from "../../runtime/db/extern";
import { bindWasmAlloc, type WasmAllocRef } from "../../wasm/core";
import { createWasiImports } from "../../runtime/wasi";
import { buildWsImports, buildHttpImports } from "../../runtime";
import type { WsState } from "../../runtime";
import type { KVNamespace } from "../../runtime/kv";
import { get, put, del, list } from "../../runtime/kv/memory";
import type { Database } from "../../runtime/db";

type ConnState = WsState & { topics: Set<string> };

const textDecoder = new TextDecoder();

function deliverToWasm(conn: ConnState, data: Uint8Array | null): void {
    if (conn.recvResolve) {
        const res = conn.recvResolve;
        conn.recvResolve = null;
        res(data);
        return;
    }
    if (data) conn.messageQueue.push(data);
}

/** Accept a WebSocketPair and wire frames into the JSPI recv loop. */
function attachWebSocketPair(ws: WsState): WebSocket {
    const WebSocketPairCtor = (globalThis as any).WebSocketPair as new () => { 0: WebSocket; 1: WebSocket };
    const pair = new WebSocketPairCtor();
    const [client, server] = Object.values(pair) as [WebSocket, WebSocket & { accept(): void }];
    ws.server = server;
    server.accept();

    // Flush after the 101 is returned so the client has completed the handshake.
    const pending = ws.pendingWrites;
    ws.pendingWrites = [];
    queueMicrotask(() => {
        for (const data of pending) {
            try {
                server.send(textDecoder.decode(data));
            } catch {
                /* closed */
            }
        }
    });

    server.addEventListener("message", (event: MessageEvent) => {
        const data =
            typeof event.data === "string"
                ? new TextEncoder().encode(event.data)
                : new Uint8Array(event.data as ArrayBuffer);
        deliverToWasm(ws as ConnState, data);
    });

    server.addEventListener("close", () => {
        deliverToWasm(ws as ConnState, null);
    });

    return client;
}

/**
 * Build a sticky long-lived fetch class for the host runtime.
 *
 * Prefer {@link stateful} so the handler reuses the app's module/kv/db.
 *
 * @internal
 */
export function createStatefulFetch(
    module: WebAssembly.Module,
    options?: {
        kv?: (env: any) => Record<string, KVNamespace>;
        db?: (env: any) => Record<string, Database>;
        imports?: (mem: () => WebAssembly.Memory) => WebAssembly.Imports;
    },
) {
    return class StatefulFetch {
        readonly state: any;
        readonly env: any;
        readonly connections = new Map<WebSocket, ConnState>();

        constructor(state: any, env: any) {
            this.state = state;
            this.env = env;
        }

        async fetch(request: Request): Promise<Response> {
            const isUpgrade = request.headers.get("upgrade")?.toLowerCase() === "websocket";
            const stdinData =
                !isUpgrade && request.body
                    ? new Uint8Array(await request.arrayBuffer())
                    : undefined;

            const { wasiImport, setMemory } = createWasiImports({ request, stdinData });

            let wasmMemory: WebAssembly.Memory = null!;
            const mem = () => wasmMemory;

            const bridgeRef: [ZxBridge | null] = [null];
            const bridgeImports = ZxBridge.createImportObject(bridgeRef);

            const Suspending = (WebAssembly as any).Suspending;
            const jspi = typeof Suspending === "function";
            if (!jspi) {
                return new Response("Sticky WebSocket fetch requires WebAssembly JSPI", { status: 501 });
            }

            const decoder = new TextDecoder();

            const connState: ConnState = {
                upgraded: false,
                server: null,
                pendingWrites: [],
                messageQueue: [],
                recvResolve: null,
                topics: new Set(),
                subscribe: (topic) => connState.topics.add(topic),
                unsubscribe: (topic) => connState.topics.delete(topic),
                publish: (topic, data) => {
                    let count = 0;
                    const text = textDecoder.decode(data);
                    for (const [sock, conn] of this.connections) {
                        if (conn.topics.has(topic)) {
                            try {
                                sock.send(text);
                                count++;
                            } catch {
                                /* closed */
                            }
                        }
                    }
                    if (!connState.server && connState.topics.has(topic)) {
                        connState.pendingWrites.push(data.slice());
                        count++;
                    }
                    return count;
                },
                isSubscribed: (topic) => connState.topics.has(topic),
            };

            const sysImports = {
                sleep_ms: new Suspending(
                    async (ms: number): Promise<void> => new Promise<void>((r) => setTimeout(r, ms)),
                ),
            };

            const wsImports = buildWsImports(Suspending, mem, decoder, connState);

            const httpState = {
                committed: false,
                ended: false,
                status: 200,
                streaming: false,
                headers: new Headers(),
                bodyChunks: [] as Uint8Array[],
                streamWriter: null as WritableStreamDefaultWriter<Uint8Array> | null,
            };

            const kvBindings = options?.kv?.(this.env);
            const dbBindings = options?.db?.(this.env);
            const allocRef: WasmAllocRef = [null];

            const importObject: WebAssembly.Imports = {
                wasi_snapshot_preview1: wasiImport,
                __zx_sys: sysImports,
                __zx_ws: wsImports,
                __zx_http: buildHttpImports(mem, httpState),
                __zx_net: createFetchImports(mem),
                ...(options?.imports ? options.imports(mem) : {}),
                ...bridgeImports,
            };
            if (typeof __FEAT_KV_SERVER__ === "undefined" || __FEAT_KV_SERVER__) {
                importObject.__zx_kv = createKVImports(
                    kvBindings ?? { default: { get, put, del, list } },
                    mem,
                    allocRef,
                );
            }
            if (typeof __FEAT_DB__ === "undefined" || __FEAT_DB__) {
                importObject.__zx_db = createDbImports(dbBindings ?? {}, mem, allocRef);
            }

            const instance = new WebAssembly.Instance(module, importObject);

            wasmMemory = instance.exports.memory as WebAssembly.Memory;
            setMemory(wasmMemory);
            bridgeRef[0] = new ZxBridge(instance.exports);
            bindWasmAlloc(allocRef, instance.exports);

            // promising() runs synchronously until the first Suspending import (ws_recv).
            const start = (WebAssembly as any).promising(instance.exports._start as Function);
            const wasmPromise = (start() as Promise<void>)
                .catch((e: unknown) => {
                    if (e instanceof Error && e.message.startsWith("proc_exit")) return;
                    console.error("[StatefulFetch] WASM error:", e);
                })
                .finally(() => {
                    if (connState.server) this.connections.delete(connState.server);
                    deliverToWasm(connState, null);
                });

            if (!connState.upgraded) {
                await wasmPromise;
                return new Response("WebSocket upgrade expected", { status: 426 });
            }

            const client = attachWebSocketPair(connState);
            this.connections.set(connState.server!, connState);
            this.state.waitUntil(wasmPromise);

            return new Response(null, { status: 101, webSocket: client } as ResponseInit);
        }
    };
}
