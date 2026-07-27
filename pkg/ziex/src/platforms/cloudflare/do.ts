import { ZxBridge } from "../../wasm";
import { createFetchImports } from "../../runtime/fetch";
import { createKVImports } from "../../runtime/kv/extern";
import { createDbImports } from "../../runtime/db/extern";
import { bindWasmAlloc, type WasmAllocRef } from "../../wasm/core";
import { createWasiImports } from "../../runtime/wasi";
import { buildWsImports, attachWebSocket } from "../../runtime";
import type { WsState } from "../../runtime";
import type { KVNamespace } from "../../runtime/kv";
import { get, put, del, list } from "../../runtime/kv/memory";
import type { Database } from "../../runtime/db";

type ConnState = WsState & { topics: Set<string> };

/**
 * Create a Durable Object class that handles WebSocket connections for a ZX app.
 *
 * Each DO instance corresponds to one "room" (keyed by pathname). All clients
 * connecting to the same route share a DO instance, enabling pub/sub via
 * `ctx.socket.subscribe()` / `ctx.socket.publish()`.
 *
 * @example
 * ```ts
 * // worker.ts
 * import { Ziex } from "ziex";
 * import { createWebSocketDO } from "ziex/cloudflare";
 * import module from "./app.wasm";
 *
 * export const ZxWS = createWebSocketDO(module);
 *
 * export default new Ziex({
 *   module,
 *   websocket: (env) => env.ZxWS,
 * });
 * ```
 */
export function createWebSocketDO(
    module: WebAssembly.Module,
    options?: {
        /**
         * KV namespace bindings for the DO. Pass a factory that receives the DO's
         * `env` so bindings are resolved at runtime:
         *
         * ```ts
         * createWebSocketDO(module, { kv: (env) => ({ default: env.KV }) })
         * ```
         */
        kv?: (env: any) => Record<string, KVNamespace>;
        db?: (env: any) => Record<string, Database>;
        imports?: (mem: () => WebAssembly.Memory) => WebAssembly.Imports;
    },
) {
    return class ZxWebSocketDO {
        readonly doState: any;
        readonly env: any;
        /** All active connections in this room, keyed by their server-side WebSocket. */
        readonly connections = new Map<WebSocket, ConnState>();

        constructor(state: any, env: any) {
            this.doState = state;
            this.env = env;
        }

        async fetch(request: Request): Promise<Response> {
            const stdinData = request.body
                ? new Uint8Array(await request.arrayBuffer())
                : undefined;

            const { wasiImport, setMemory } = createWasiImports({ request, stdinData });

            let wasmMemory: WebAssembly.Memory = null!;
            const mem = () => wasmMemory;

            const bridgeRef: [ZxBridge | null] = [null];
            const bridgeImports = ZxBridge.createImportObject(bridgeRef);

            const Suspending = (WebAssembly as any).Suspending;
            const jspi = typeof Suspending === 'function';
            const decoder = new TextDecoder();

            // Resolves when WASM first calls ws_recv (i.e. after upgrade + socket_open).
            let _resolveFirstSuspend!: () => void;
            const firstSuspendPromise = new Promise<void>((resolve) => { _resolveFirstSuspend = resolve; });

            let wasmExited = false;

            const connState: ConnState = {
                upgraded: false,
                server: null,
                pendingWrites: [],
                messageQueue: [],
                recvResolve: null,
                _resolveFirstSuspend,
                topics: new Set(),
                subscribe: (topic) => connState.topics.add(topic),
                unsubscribe: (topic) => connState.topics.delete(topic),
                publish: (topic, data) => {
                    let count = 0;
                    for (const [ws, conn] of this.connections) {
                        if (conn.topics.has(topic)) {
                            try { ws.send(data as BufferSource); count++; } catch { /* closed */ }
                        }
                    }
                    // During socket_open the server WebSocket doesn't exist yet,
                    // so the connection isn't in the map. Buffer self-publishes so
                    // they're flushed when attachWebSocket is called.
                    if (!connState.server && connState.topics.has(topic)) {
                        connState.pendingWrites.push(data.slice());
                        count++;
                    }
                    return count;
                },
                isSubscribed: (topic) => connState.topics.has(topic),
            };

            const sysImports = {
                sleep_ms: jspi
                    ? new Suspending(async (ms: number): Promise<void> =>
                        new Promise<void>((r) => setTimeout(r, ms)))
                    : (_ms: number) => {},
            };

            const wsImports = buildWsImports(jspi ? Suspending : null, mem, decoder, connState);

            const kvBindings = options?.kv?.(this.env);
            const dbBindings = options?.db?.(this.env);
            const allocRef: WasmAllocRef = [null];

            const importObject: WebAssembly.Imports = {
                wasi_snapshot_preview1: wasiImport,
                __zx_sys: sysImports,
                __zx_ws: wsImports,
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
                importObject.__zx_db = createDbImports(
                    dbBindings ?? {},
                    mem,
                    allocRef,
                );
            }

            const instance = new WebAssembly.Instance(module, importObject);

            wasmMemory = instance.exports.memory as WebAssembly.Memory;
            setMemory(wasmMemory);
            bridgeRef[0] = new ZxBridge(instance.exports);
            bindWasmAlloc(allocRef, instance.exports);

            const start = (WebAssembly as any).promising(instance.exports._start as Function);

            const wasmPromise = (start() as Promise<void>)
                .catch((e: unknown) => {
                    wasmExited = true;
                    if (e instanceof Error && e.message.startsWith("proc_exit")) return;
                    console.error("[ZxWebSocketDO] WASM error:", e);
                })
                .finally(() => {
                    // Remove from the shared map so publish() skips closed connections
                    if (connState.server) this.connections.delete(connState.server);
                    if (connState.recvResolve) {
                        const res = connState.recvResolve;
                        connState.recvResolve = null;
                        res(null);
                    }
                });

            // Wait until WASM has entered the receive loop (or exited without upgrading).
            await Promise.race([firstSuspendPromise, wasmPromise]);

            if (!connState.upgraded || wasmExited) {
                return new Response("WebSocket upgrade expected", { status: 426 });
            }

            const { client } = attachWebSocket(connState);
            // Register in the shared map so publish() can reach this connection
            this.connections.set(connState.server!, connState);
            // Keep the DO alive while WASM handles the message loop
            this.doState.waitUntil(wasmPromise);

            return new Response(null, { status: 101, webSocket: client } as ResponseInit);
        }
    };
}
